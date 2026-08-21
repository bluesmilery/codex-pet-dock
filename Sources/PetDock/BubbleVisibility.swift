import Cocoa
import os
import ScreenCaptureKit

// MARK: - 会话气泡可见性（ScreenCaptureKit 像素 alpha 判定）

/// 会话气泡是否实际绘制内容（展开 vs 收起）。
/// - visible：有内容（展开）→ 作为障碍避让。
/// - hidden：空/收起 → 不避让，dock 回 pet 下方。
enum BubbleVisibility: Equatable, Sendable {
    case visible
    case hidden
}

/// 实测校准阈值（同窗口 345×64 真实 collapsed vs expanded 对照）。
/// collapsed: nonTransparent 34/22080≈0.154%, bbox 48/22080≈0.217%
/// expanded:  nonTransparent 189/22080≈0.856%, bbox 390/22080≈1.766%
/// open/close 之间留滞回区，防抖动。
enum BubbleVisibilityThresholds {
    /// 判 visible：非透明占比 ≥ 此值（0.6%，在 collapsed 0.154% 与 expanded 0.856% 之间）。
    static let openNonTransparent: Double = 0.006
    /// 判 visible：bbox 占比 ≥ 此值（1.0%，在 collapsed 0.217% 与 expanded 1.766% 之间）。
    static let openBBox: Double = 0.010
    /// 判 hidden：非透明占比 ≤ 此值（0.3%）。
    static let closeNonTransparent: Double = 0.003
    /// 判 hidden：bbox 占比 ≤ 此值（0.5%）。
    static let closeBBox: Double = 0.005
}

/// 匿名像素 alpha 统计（不记录颜色/文字/图像）。
struct BubbleAlphaStats: Equatable, Sendable {
    let nonTransparentRatio: Double   // alpha>0.04 像素 / 总像素
    let bboxRatio: Double             // 非透明 bbox 面积 / 总像素
}

/// ScreenCaptureKit 观察结果的最小策略相关语义。
/// - stats：成功取得目标窗口并完成匿名 alpha 统计。
/// - targetMissing：成功取得窗口清单，但该 generation 的目标 WID 不在清单中。
/// - unavailable：权限、清单、截图或统计不可用；必须保守避让。
enum BubbleCaptureOutcome: Equatable, Sendable {
    case stats(BubbleAlphaStats)
    case targetMissing
    case unavailable
}

/// CGWindowList 候选的最小身份快照。WID 重用或同 WID 的几何/owner 变化时，
/// 旧 capture completion 不得写入新候选的可见性 cache。
struct BubbleCandidateIdentity: Equatable, Sendable {
    let ownerPID: Int32
    let ownerName: String
    let title: String
    let layer: Int
    let alpha: Double
    let isOnscreen: Bool
    let sharingState: Int
    let bounds: CGRect

    init(_ candidate: WinCandidate) {
        ownerPID = candidate.ownerPID
        ownerName = candidate.ownerName
        title = candidate.title
        layer = candidate.layer
        alpha = candidate.alpha
        isOnscreen = candidate.isOnscreen
        sharingState = candidate.sharingState
        bounds = candidate.bounds
    }
}

/// 纯函数分类（有滞回）。
/// - stats 有值：按 alpha 阈值判 visible/hidden，中间区滞回（沿用 previous）。
/// - unavailable（capture 失败 / macOS 13 / TCC 抖动）→ `.visible`（保守避让）。
///   README 契约："on macOS 13 or capture failure, it conservatively avoids"。
///   当前仍存在的气泡（wid 在候选集内），capture 失败时必须保守当障碍避让，
///   不能因 unavailable 误判为收起导致底座重叠气泡。
///   收起态的正确复位由已观察 WID 的 targetMissing 结果或
///   `BubbleVisibilityProbe.knownWids` 失效机制承担，不依赖 unavailable。
enum BubbleVisibilityClassifier {
    static func classify(stats: BubbleAlphaStats?, previous: BubbleVisibility) -> BubbleVisibility {
        guard let s = stats else { return .visible }
        return classify(stats: s, previous: previous)
    }

    static func classify(stats: BubbleAlphaStats, previous: BubbleVisibility) -> BubbleVisibility {
        if stats.nonTransparentRatio >= BubbleVisibilityThresholds.openNonTransparent
            || stats.bboxRatio >= BubbleVisibilityThresholds.openBBox { return .visible }
        if stats.nonTransparentRatio <= BubbleVisibilityThresholds.closeNonTransparent
            && stats.bboxRatio <= BubbleVisibilityThresholds.closeBBox { return .hidden }
        return previous   // 中间滞回
    }

    static func classify(
        outcome: BubbleCaptureOutcome,
        previous: BubbleVisibility,
        hasSuccessfulObservation: Bool
    ) -> BubbleVisibility {
        switch outcome {
        case .stats(let stats):
            return classify(stats: stats, previous: previous)
        case .targetMissing:
            return hasSuccessfulObservation ? .hidden : .visible
        case .unavailable:
            return .visible
        }
    }
}

/// 像素捕获器接口（@Sendable 闭包，后台 Task 安全传递）。
typealias BubbleCapturer = @Sendable (WinCandidate) async -> BubbleCaptureOutcome

/// 单进程启动期权限请求 gate：已授权不请求，未授权也至多请求一次。
struct ScreenCapturePermissionRequestGate {
    private var didRequest = false

    mutating func shouldRequest(preflightGranted: Bool) -> Bool {
        guard !preflightGranted, !didRequest else { return false }
        didRequest = true
        return true
    }
}

/// 异步探测 obstaclesNear 候选的可见性。`Sendable`（状态由 `OSAllocatedUnfairLock` 保护）。
/// 最长 0.1s 受控启动等待、single-flight（generation 严格）、保守降级（失败/macOS13 → visible）。
/// 像素捕获在 `Task.detached` 后台执行（不跑主线程），完成后经 lock + generation 校验更新。
final class BubbleVisibilityProbe: Sendable {
    static let minInterval: TimeInterval = 0.1

    /// 受锁保护的可变状态（同 module 测试可经 lock 访问）。
    internal struct ProbeState: Sendable {
        var cached: [CGWindowID: BubbleVisibility] = [:]
        var lastCaptureAt: TimeInterval = -.greatestFiniteMagnitude
        var inFlight = false
        var pendingRetryAt: TimeInterval?
        /// 候选版本：候选集合/identity 变化或 reset 递增。旧 Task 回调 generation 不匹配时丢弃。
        var generation = 0
        /// 最近一次 `probe(candidates:)` 传入的 wid 集合（当前帧实际存在的候选）。
        /// `visibility(for:)` 对不在此集合中的 wid 返回 `.hidden`（当前帧失效），
        /// 防止已从 obstaclesNear 消失的候选残留 visible 缓存导致底座不复位（回归 A）。
        var knownWids: Set<CGWindowID> = []
        /// 当前候选 WID 对应的完整身份快照；同 WID 但 bounds/owner/layer 变化也会换 generation。
        var knownCandidates: [CGWindowID: BubbleCandidateIdentity] = [:]
        /// 当前 generation 内至少一次成功取得 alpha 统计的目标 WID。
        /// 只有这些 WID 的后续 targetMissing 才是权威 hidden；unavailable 永远保守 visible。
        var successfullyObservedWids: Set<CGWindowID> = []
    }

    internal let lock: OSAllocatedUnfairLock<ProbeState>
    private let monotonicNow: @Sendable () -> TimeInterval
    private let canCapture: @Sendable () -> Bool
    private let capturer: BubbleCapturer
    private let evidence: (any RuntimeEvidenceRecording)?
    private let onVisibilityChange: @Sendable () -> Void

    init(monotonicNow: @escaping @Sendable () -> TimeInterval = { ProcessInfo.processInfo.systemUptime },
         canCapture: @escaping @Sendable () -> Bool = { CGPreflightScreenCaptureAccess() },
         capturer: BubbleCapturer? = nil,
         evidence: (any RuntimeEvidenceRecording)? = nil,
         onVisibilityChange: @escaping @Sendable () -> Void = {}) {
        self.lock = OSAllocatedUnfairLock(initialState: ProbeState())
        self.monotonicNow = monotonicNow
        self.canCapture = canCapture
        self.capturer = capturer ?? Self.defaultCapturer
        self.evidence = evidence
        self.onVisibilityChange = onVisibilityChange
    }

    // MARK: - 主线程接口（tick 同步调用）

    /// 是否可触发探测（0.1s cadence + single-flight）。
    func isDue(_ time: TimeInterval) -> Bool {
        lock.withLock { s in
            !s.inFlight && time - s.lastCaptureAt >= Self.minInterval
        }
    }

    /// 异步探测候选（如果 due 且无在途）。后台 Task 捕获 → generation 校验 → 更新 cached。
    /// 无论是否启动捕获，都同步刷新 `knownWids` 为当前候选 wid 集合 —— 这是当前帧的几何事实，
    /// 必须每帧立即生效，使 `visibility(for:)` 对已消失候选返回 `.hidden`（当前帧失效，回归 A）。
    func probe(candidates: [WinCandidate]) {
        let gen: Int
        let prev: [CGWindowID: BubbleVisibility]
        let previouslyObserved: Set<CGWindowID>
        let capturedCandidates: [CGWindowID: BubbleCandidateIdentity]
        let shouldStart: Bool
        let identityChanged: Bool
        let captureAllowed = !candidates.isEmpty && canCapture()
        (gen, prev, previouslyObserved, capturedCandidates, shouldStart, identityChanged) = lock.withLock { s -> (Int, [CGWindowID: BubbleVisibility], Set<CGWindowID>, [CGWindowID: BubbleCandidateIdentity], Bool, Bool) in
            s.pendingRetryAt = nil
            // 同步刷新 knownWids：当前帧实际存在的候选 wid（每帧事实，立即生效）。
            let nextWids = Set(candidates.map { $0.wid })
            let nextCandidates = candidates.reduce(into: [CGWindowID: BubbleCandidateIdentity]()) { result, candidate in
                result[candidate.wid] = BubbleCandidateIdentity(candidate)
            }
            let candidatesChanged = s.knownWids != nextWids || s.knownCandidates != nextCandidates
            if candidatesChanged {
                s.generation += 1
                s.cached.removeAll()
                s.successfullyObservedWids.removeAll()
            }
            let identityChanged = candidatesChanged && !candidates.isEmpty
            s.knownWids = nextWids
            s.knownCandidates = nextCandidates
            guard !candidates.isEmpty else {
                // 完全空闲（无候选 + 无缓存 + 无在途）→ 无意义锁写，直接 return。
                // 宠物可见但下方无会话气泡时，moving 态会高频调用 probe([])，
                // 此早退避免每帧递增 generation + 清空字典的无意义锁写。
                if s.cached.isEmpty && s.successfullyObservedWids.isEmpty && !s.inFlight {
                    return (0, [:], [], [:], false, false)
                }
                // 仍有缓存或在途：与 reset() 一致递增 generation + 清 cached，使旧结果失效。
                // 旧 Task 仍持有唯一 token，完成时清 inFlight；期间候选重新出现 probe 被拒。
                s.generation += 1
                s.cached.removeAll()
                s.successfullyObservedWids.removeAll()
                return (0, [:], [], [:], false, false)
            }
            guard captureAllowed else {
                // 权限尚未对本进程生效：不进入 ScreenCaptureKit，并清除旧 hidden 缓存，
                // 使当前仍存在的候选按默认 `.visible` 保守避让。旧在途结果通过 generation 失效。
                if !s.cached.isEmpty || !s.successfullyObservedWids.isEmpty || s.inFlight {
                    s.generation += 1
                    s.cached.removeAll()
                    s.successfullyObservedWids.removeAll()
                }
                return (0, [:], [], [:], false, identityChanged)
            }
            let time = monotonicNow()
            guard !s.inFlight else {
                return (0, [:], [], [:], false, identityChanged)
            }
            let elapsed = time - s.lastCaptureAt
            guard elapsed >= Self.minInterval else {
                s.pendingRetryAt = s.lastCaptureAt + Self.minInterval
                return (0, [:], [], [:], false, identityChanged)
            }
            s.inFlight = true
            s.lastCaptureAt = time
            return (s.generation, s.cached, s.successfullyObservedWids, s.knownCandidates, true, identityChanged)
        }
        // identity telemetry 必须在 capture gate 之前：候选非空且 known identity 变化时，
        // 即使 capture 未 due 或 inFlight（shouldStart=false），H4b 的 identity 抖动也不能漏计。
        if identityChanged { evidence?.recordIdentityChange() }
        guard shouldStart else { return }
        let cap = capturer
        let notify = onVisibilityChange
        // Task.detached：不捕获 self（仅捕获 Sendable 值 lock/cap/gen/prev/candidates/identity）→ 0 #SendableClosureCaptures warning。
        // 像素计算（cap → captureStats → computeAlphaStats）在后台线程执行。
        // evidence 只接收枚举计数（outcome kind + classified visibility），不接收 alpha 统计值。
        // 计数延迟到 completion 的 generation+identity 接受校验之后：
        // stale/过期 in-flight 结果不写 cache，也绝不进入真实统计。
        Task.detached { [lock, evidence] in
            var r: [CGWindowID: BubbleVisibility] = [:]
            var observedWids = Set<CGWindowID>()
            var evidencePairs: [(RuntimeCaptureOutcomeKind, BubbleVisibility)] = []
            for c in candidates {
                let outcome = await cap(c)
                let classified = BubbleVisibilityClassifier.classify(
                    outcome: outcome,
                    previous: prev[c.wid] ?? .visible,
                    hasSuccessfulObservation: previouslyObserved.contains(c.wid)
                )
                if evidence != nil {
                    let kind: RuntimeCaptureOutcomeKind
                    switch outcome {
                    case .stats: kind = .stats
                    case .targetMissing: kind = .targetMissing
                    case .unavailable: kind = .unavailable
                    }
                    evidencePairs.append((kind, classified))
                }
                if case .stats = outcome { observedWids.insert(c.wid) }
                r[c.wid] = classified
            }
            let results = r   // var→let：lock 闭包只捕获不可变 Sendable 值
            let successfulWids = observedWids
            // generation 校验：旧 Task 回调（reset/候选切换后）仅清自己的 inFlight token，绝不写 cached。
            let (didChange, accepted): (Bool, Bool) = lock.withLock { s -> (Bool, Bool) in
                s.inFlight = false   // 始终清 inFlight（旧 Task 的责任，保证新 probe 能在下一 tick 启动）
                guard s.generation == gen,
                      s.knownCandidates == capturedCandidates else { return (false, false) } // generation/identity 过期 → 不写 cached/通知/证据
                let changed = results.contains { entry in
                    s.knownWids.contains(entry.key)
                        && (s.cached[entry.key] ?? .visible) != entry.value
                }
                s.cached = results
                s.successfullyObservedWids.formUnion(successfulWids)
                return (changed, true)
            }
            if accepted, let evidence {
                for pair in evidencePairs { evidence.recordCapture(kind: pair.0, visibility: pair.1) }
            }
            if didChange {
                evidence?.recordWakeCallback()
                notify()
            }
        }
    }

    /// 当前完整布局 tick 因 cadence 尚未 due 时，取走距下次允许捕获的剩余等待。
    /// in-flight、无候选或无权限不产生该 hint，继续沿用 scheduler 原 cadence。
    func takePendingRetryDelay() -> TimeInterval? {
        let deadline = lock.withLock { state -> TimeInterval? in
            defer { state.pendingRetryAt = nil }
            return state.pendingRetryAt
        }
        guard let deadline else { return nil }
        return max(0, deadline - monotonicNow())
    }

    /// 同步读缓存（tick 主线程，非阻塞）。
    /// - wid 在当前帧候选集（knownWids）中：返回 cached 结果；尚未完成首次探测 → `.visible`（保守避让）。
    /// - wid 不在当前帧候选集（已从 obstaclesNear 消失）→ `.hidden`（当前帧失效，复位，回归 A）。
    func visibility(for wid: CGWindowID) -> BubbleVisibility {
        lock.withLock {
            guard $0.knownWids.contains(wid) else { return .hidden }
            return $0.cached[wid] ?? .visible
        }
    }

    /// 候选/宠物消失 → 递增 generation（旧 Task 回调失效）+ 清 cached/knownWids/knownCandidates。
    /// **不设 inFlight=false**：旧 Task 在途时由其自身回调清 inFlight，保证 reset 期间新 probe 不启动（strict single-flight）。
    func reset() {
        lock.withLock { s in
            s.generation += 1
            s.cached.removeAll()
            s.knownWids.removeAll()
            s.knownCandidates.removeAll()
            s.successfullyObservedWids.removeAll()
            s.pendingRetryAt = nil
        }
    }

    // MARK: - 默认捕获器（macOS 14+ ScreenCaptureKit，macOS 13/失败 → unavailable 保守 visible）

    private static let defaultCapturer: BubbleCapturer = { candidate in
        guard #available(macOS 14.0, *) else { return .unavailable }
        return await captureStats(candidate)
    }

    // MARK: - ScreenCaptureKit 捕获（static，后台执行）

    @available(macOS 14.0, *)
    private static func captureStats(_ candidate: WinCandidate) async -> BubbleCaptureOutcome {
        let content: SCShareableContent
        do {
            content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
        } catch {
            return .unavailable
        }
        guard let win = content.windows.first(where: { $0.windowID == candidate.wid }) else {
            return .targetMissing
        }
        let filter = SCContentFilter(desktopIndependentWindow: win)
        let config = SCStreamConfiguration()
        config.width = Int(candidate.bounds.width.rounded())
        config.height = Int(candidate.bounds.height.rounded())
        config.scalesToFit = false
        config.showsCursor = false
        guard let img = try? await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config) else {
            return .unavailable
        }
        return .stats(computeAlphaStats(image: img))
    }

    /// 内存计算 alpha 统计（不保存图/OCR/记录颜色文字）。static → 后台 Task 内执行。
    static func computeAlphaStats(image: CGImage) -> BubbleAlphaStats {
        let rep = NSBitmapImageRep(cgImage: image)
        let w = rep.pixelsWide, h = rep.pixelsHigh
        guard w > 0, h > 0 else { return BubbleAlphaStats(nonTransparentRatio: 0, bboxRatio: 0) }
        let total = Double(w * h)
        var nonTrans = 0, minX = w, minY = h, maxX = 0, maxY = 0
        for y in 0..<h {
            for x in 0..<w {
                guard let c = rep.colorAt(x: x, y: y) else { continue }
                if c.alphaComponent > 0.04 {
                    nonTrans += 1
                    if x < minX { minX = x }; if x > maxX { maxX = x }
                    if y < minY { minY = y }; if y > maxY { maxY = y }
                }
            }
        }
        let bbox = nonTrans > 0 ? Double((maxX - minX + 1) * (maxY - minY + 1)) : 0
        return BubbleAlphaStats(nonTransparentRatio: Double(nonTrans) / total, bboxRatio: bbox / total)
    }
}
