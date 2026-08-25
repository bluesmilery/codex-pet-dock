import Cocoa
import os
import ScreenCaptureKit

// MARK: - 会话气泡可见性（ScreenCaptureKit 像素 alpha 判定）

/// 会话气泡是否实际绘制可见内容。
/// - visible：有可见内容（非透明像素数 ≥ 噪声下限）→ 作为障碍按内容 bbox 避让。
/// - hidden：无内容 / 低于噪声下限 → 不避让，dock 回 pet 下方。
enum BubbleVisibility: Equatable, Sendable {
    case visible
    case hidden
}

/// 可见内容噪声下限（像素数）。2026-08-24 现场像素级校准：宿主收起后 ACT 容器仅剩
/// 39-57 个非透明像素的不可见小点（6-7px 宽、窗口内 y[21,28]，截屏放大肉眼不可见）；
/// 控制按钮出现时实测 189-194px。取 80：噪声上 margin 57<80、按钮下 margin 80<189，
/// 双向 ≥40% 余量。旧阈值 3 基于“25/34px 可见横条”旧测量，已被新现场证据取代。
/// 该阈值只影响“有无内容”判定；Composition Surface 因宠物像素恒为 visible，不受影响。
enum BubbleVisibilityThresholds {
    /// 非透明像素数 ≥ 此值判 visible（有内容）；低于此值判 hidden（噪声/全透明）。
    static let minContentPixels = 80
    /// 窗口面积（原始像素）超过该值的候选捕获时等比降采样（性能保护：
    /// Composition Surface 768x912 大窗若全尺寸捕获并逐像素统计，7 个实例不可接受）。
    static let downsampleAreaThreshold: Double = 100_000
    /// 降采样后最长边上限（像素）；像素探测只需内容底边，几像素误差可接受。
    static let downsampleMaxSide: CGFloat = 240
}

/// 匿名像素 alpha 统计（不记录颜色/文字/图像）。
struct BubbleAlphaStats: Equatable, Sendable {
    let nonTransparentPixelCount: Int   // alpha>0.04 像素数（噪声下限输入）
    /// 非透明内容的窗口内像素底边（maxY）；无内容时为 -1。
    /// 避让矩形高度 = contentBottom+1，使 dock 紧贴可见内容而非整窗 bounds。
    let contentBottom: Int
}

/// 单个气泡候选最近一次已分类观察结果：可见性 + 可见内容的窗口内底边。
/// - contentBottom 仅来自成功像素统计且判 visible；保守 visible（unavailable / 尚未完成
///   首次观察）为 nil —— 布局退回整窗 bounds 避让（无内容信息时的保守占位）。
struct BubbleObservation: Equatable, Sendable {
    let visibility: BubbleVisibility
    let contentBottom: Int?
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

    /// 除 bounds 外的身份字段是否完全一致（同窗口纯几何平移/缩放判定）。
    /// 拖动宠物时气泡窗口 bounds 逐帧跟随变化，但 WID/owner/title/layer/alpha/onscreen/
    /// sharing 均不变；这类纯几何变化保留可见性 cache（粘性），不当作候选身份切换。
    /// 代价：拖动期间展开/收起的真实状态变化最迟在拖动结束后的下一次捕获（≤0.1s cadence
    /// + 捕获耗时）收敛——接受的权衡；捕获写入校验仍要求 knownCandidates 精确相等，
    /// bounds 平移期间启动的旧捕获结果不会写入新几何。
    func sameWindowIgnoringBounds(_ other: BubbleCandidateIdentity) -> Bool {
        ownerPID == other.ownerPID
            && ownerName == other.ownerName
            && title == other.title
            && layer == other.layer
            && alpha == other.alpha
            && isOnscreen == other.isOnscreen
            && sharingState == other.sharingState
    }
}

/// 纯函数分类（按可见内容，无滞回）。
/// - stats：非透明像素数 ≥ 噪声下限 → visible（携带内容底边）；否则 hidden。
/// - targetMissing：同 generation 已成功观察过 → hidden；从未观察过 → 保守 visible。
/// - unavailable（capture 失败 / macOS 13 / TCC 抖动）→ `.visible`（保守避让）。
///   README 契约："on macOS 13 or capture failure, it conservatively avoids"。
///   当前仍存在的气泡（wid 在候选集内），capture 失败时必须保守当障碍避让，
///   不能因 unavailable 误判为收起导致底座重叠气泡。
///   收起态的正确复位由已观察 WID 的 targetMissing 结果或
///   `BubbleVisibilityProbe.knownWids` 失效机制承担，不依赖 unavailable。
enum BubbleVisibilityClassifier {
    static func classify(stats: BubbleAlphaStats) -> BubbleObservation {
        guard stats.nonTransparentPixelCount >= BubbleVisibilityThresholds.minContentPixels else {
            return BubbleObservation(visibility: .hidden, contentBottom: nil)
        }
        return BubbleObservation(visibility: .visible, contentBottom: stats.contentBottom)
    }

    static func classify(
        outcome: BubbleCaptureOutcome,
        hasSuccessfulObservation: Bool
    ) -> BubbleObservation {
        switch outcome {
        case .stats(let stats):
            return classify(stats: stats)
        case .targetMissing:
            return BubbleObservation(
                visibility: hasSuccessfulObservation ? .hidden : .visible,
                contentBottom: nil)
        case .unavailable:
            return BubbleObservation(visibility: .visible, contentBottom: nil)
        }
    }
}

/// 像素捕获器接口（@Sendable 闭包，后台 Task 安全传递）。
typealias BubbleCapturer = @Sendable (WinCandidate) async -> BubbleCaptureOutcome
/// 每轮探测先创建一次 capturer；默认实现共享一次 ScreenCaptureKit 窗口清单枚举。
typealias BubbleCapturerFactory = @Sendable () async -> BubbleCapturer

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
    static let stableProbeInterval: TimeInterval = 1.0

    /// 受锁保护的可变状态（同 module 测试可经 lock 访问）。
    internal struct ProbeState: Sendable {
        var cached: [CGWindowID: BubbleObservation] = [:]
        var lastCaptureAt: TimeInterval = -.greatestFiniteMagnitude
        var inFlight = false
        var pendingRetryAt: TimeInterval?
        /// 窗口身份不稳定时使用 0.1s 快速节奏；捕获启动后切回 1.0s 低频心跳。
        var identityDirty = true
        /// 候选版本：候选集合/identity 变化或 reset 递增。旧 Task 回调 generation 不匹配时丢弃。
        var generation = 0
        /// 最近一次 `probe(candidates:)` 传入的 wid 集合（当前帧实际存在的候选）。
        /// `visibility(for:)` 对不在此集合中的 wid 返回 `.hidden`（当前帧失效），
        /// 防止已从 obstaclesNear 消失的候选残留 visible 缓存导致底座不复位（回归 A）。
        var knownWids: Set<CGWindowID> = []
        /// 当前候选 WID 对应的完整身份快照；同 WID 但任一非 bounds 身份字段变化会换 generation
        /// （纯 bounds 平移/缩放不换，见 probe 的粘性可见性判定）。
        var knownCandidates: [CGWindowID: BubbleCandidateIdentity] = [:]
        /// 当前 generation 内至少一次成功取得 alpha 统计的目标 WID。
        /// 只有这些 WID 的后续 targetMissing 才是权威 hidden；unavailable 永远保守 visible。
        var successfullyObservedWids: Set<CGWindowID> = []
    }

    internal let lock: OSAllocatedUnfairLock<ProbeState>
    private let monotonicNow: @Sendable () -> TimeInterval
    private let canCapture: @Sendable () -> Bool
    private let makeCapturer: BubbleCapturerFactory
    private let evidence: (any RuntimeEvidenceRecording)?
    private let onVisibilityChange: @Sendable () -> Void

    init(monotonicNow: @escaping @Sendable () -> TimeInterval = { ProcessInfo.processInfo.systemUptime },
                 canCapture: @escaping @Sendable () -> Bool = { CGPreflightScreenCaptureAccess() },
                 capturer: BubbleCapturer? = nil,
                 makeCapturer: BubbleCapturerFactory? = nil,
                 evidence: (any RuntimeEvidenceRecording)? = nil,
                 onVisibilityChange: @escaping @Sendable () -> Void = {}) {
        self.lock = OSAllocatedUnfairLock(initialState: ProbeState())
        self.monotonicNow = monotonicNow
        self.canCapture = canCapture
        if let capturer {
            self.makeCapturer = { capturer }
        } else {
            self.makeCapturer = makeCapturer ?? Self.defaultMakeCapturer
        }
        self.evidence = evidence
        self.onVisibilityChange = onVisibilityChange
    }

    // MARK: - 主线程接口（tick 同步调用）

    /// 是否可触发探测（0.1s cadence + single-flight）。
    func isDue(_ time: TimeInterval) -> Bool {
        lock.withLock { s in
            let interval = s.identityDirty ? Self.minInterval : Self.stableProbeInterval
            return !s.inFlight && time - s.lastCaptureAt >= interval
        }
    }

    /// 异步探测候选（如果 due 且无在途）。后台 Task 捕获 → generation 校验 → 更新 cached。
    /// 无论是否启动捕获，都同步刷新 `knownWids` 为当前候选 wid 集合 —— 这是当前帧的几何事实，
    /// 必须每帧立即生效，使 `visibility(for:)` 对已消失候选返回 `.hidden`（当前帧失效，回归 A）。
    func probe(candidates: [WinCandidate]) {
        let gen: Int
        let previouslyObserved: Set<CGWindowID>
        let capturedCandidates: [CGWindowID: BubbleCandidateIdentity]
        let shouldStart: Bool
        let identityChanged: Bool
        let captureAllowed = !candidates.isEmpty && canCapture()
        (gen, previouslyObserved, capturedCandidates, shouldStart, identityChanged) = lock.withLock { s -> (Int, Set<CGWindowID>, [CGWindowID: BubbleCandidateIdentity], Bool, Bool) in
            s.pendingRetryAt = nil
            // 同步刷新 knownWids：当前帧实际存在的候选 wid（每帧事实，立即生效）。
            let nextWids = Set(candidates.map { $0.wid })
            let nextCandidates = candidates.reduce(into: [CGWindowID: BubbleCandidateIdentity]()) { result, candidate in
                result[candidate.wid] = BubbleCandidateIdentity(candidate)
            }
            let widsChanged = s.knownWids != nextWids
            // 纯几何 vs 真身份：WID 集合相同且除 bounds 外身份字段全部一致 → 只是窗口平移/缩放
            // （拖动宠物时气泡窗口逐帧跟随）。此时保留 cache 与 successfullyObservedWids（粘性）
            // 且不递增 generation，避免拖动期间每帧清空 cache 使 visibility(for:) 回落默认
            // .visible、dock 持续避让隐藏气泡（拖动期间宠物与底座之间出现空白的根因）。
            // WID 集合或任一身份字段变化（WID 重用/owner/layer/alpha/...）→ 维持现行
            // generation 递增 + cache/observed 清空 + 保守 visible。写入校验不变：完成回调仍
            // 要求 generation 与 knownCandidates 完全相等，拖动中在途的旧捕获结果一律丢弃。
            var windowIdentityChanged = widsChanged
            if !windowIdentityChanged {
                for (wid, identity) in nextCandidates
                where s.knownCandidates[wid]?.sameWindowIgnoringBounds(identity) != true {
                    windowIdentityChanged = true
                    break
                }
            }
            let candidatesChanged = widsChanged || s.knownCandidates != nextCandidates
            if windowIdentityChanged {
                s.generation += 1
                s.cached.removeAll()
                s.successfullyObservedWids.removeAll()
                s.identityDirty = true
            }
            let identityChanged = candidatesChanged && !candidates.isEmpty
            s.knownWids = nextWids
            s.knownCandidates = nextCandidates
            guard !candidates.isEmpty else {
                // 完全空闲（无候选 + 无缓存 + 无在途）→ 无意义锁写，直接 return。
                // 宠物可见但下方无会话气泡时，moving 态会高频调用 probe([])，
                // 此早退避免每帧递增 generation + 清空字典的无意义锁写。
                if s.cached.isEmpty && s.successfullyObservedWids.isEmpty && !s.inFlight {
                    return (0, [], [:], false, false)
                }
                // 仍有缓存或在途：与 reset() 一致递增 generation + 清 cached，使旧结果失效。
                // 旧 Task 仍持有唯一 token，完成时清 inFlight；期间候选重新出现 probe 被拒。
                s.generation += 1
                s.cached.removeAll()
                s.successfullyObservedWids.removeAll()
                return (0, [], [:], false, false)
            }
            guard captureAllowed else {
                // 权限尚未对本进程生效：不进入 ScreenCaptureKit，并清除旧 hidden 缓存，
                // 使当前仍存在的候选按默认 `.visible` 保守避让。旧在途结果通过 generation 失效。
                if !s.cached.isEmpty || !s.successfullyObservedWids.isEmpty || s.inFlight {
                    s.generation += 1
                    s.cached.removeAll()
                    s.successfullyObservedWids.removeAll()
                }
                return (0, [], [:], false, identityChanged)
            }
            let time = monotonicNow()
            guard !s.inFlight else {
                return (0, [], [:], false, identityChanged)
            }
            let elapsed = time - s.lastCaptureAt
            let interval = s.identityDirty ? Self.minInterval : Self.stableProbeInterval
            guard elapsed >= interval else {
                s.pendingRetryAt = s.lastCaptureAt + interval
                return (0, [], [:], false, identityChanged)
            }
            s.inFlight = true
            s.lastCaptureAt = time
            s.identityDirty = false
            return (s.generation, s.successfullyObservedWids, s.knownCandidates, true, identityChanged)
        }
        // identity telemetry 必须在 capture gate 之前：候选非空且 known identity 变化时，
        // 即使 capture 未 due 或 inFlight（shouldStart=false），H4b 的 identity 抖动也不能漏计。
        if identityChanged { evidence?.recordIdentityChange() }
        guard shouldStart else { return }
        let makeCapturer = self.makeCapturer
        let notify = onVisibilityChange
        // Task.detached：不捕获 self（仅捕获 Sendable 值 lock/cap/gen/observed/candidates/identity）→ 0 #SendableClosureCaptures warning。
        // 像素计算（cap → captureStats → computeAlphaStats）在后台线程执行。
        // evidence 只接收枚举计数（outcome kind + classified visibility），不接收 alpha 统计值。
        // 计数延迟到 completion 的 generation+identity 接受校验之后：
        // stale/过期 in-flight 结果不写 cache，也绝不进入真实统计。
        Task.detached { [lock, evidence] in
            let cap = await makeCapturer()
            var r: [CGWindowID: BubbleObservation] = [:]
            var observedWids = Set<CGWindowID>()
            var evidencePairs: [(RuntimeCaptureOutcomeKind, BubbleVisibility)] = []
            for c in candidates {
                let outcome = await cap(c)
                let observation = BubbleVisibilityClassifier.classify(
                    outcome: outcome,
                    hasSuccessfulObservation: previouslyObserved.contains(c.wid)
                )
                if evidence != nil {
                    let kind: RuntimeCaptureOutcomeKind
                    switch outcome {
                    case .stats: kind = .stats
                    case .targetMissing: kind = .targetMissing
                    case .unavailable: kind = .unavailable
                    }
                    evidencePairs.append((kind, observation.visibility))
                }
                if case .stats = outcome { observedWids.insert(c.wid) }
                r[c.wid] = observation
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
                        && (s.cached[entry.key]?.visibility ?? .visible) != entry.value.visibility
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

    /// 同步读缓存观察结果（tick 主线程，非阻塞）。
    /// - wid 在当前帧候选集（knownWids）中：返回 cached 观察；尚未完成首次探测 → 保守
    ///   `.visible` 且 contentBottom=nil（无内容信息 → 整窗避让）。
    /// - wid 不在当前帧候选集（已从 obstaclesNear 消失）→ `.hidden`（当前帧失效，复位，回归 A）。
    func observation(for wid: CGWindowID) -> BubbleObservation {
        lock.withLock {
            guard $0.knownWids.contains(wid) else {
                return BubbleObservation(visibility: .hidden, contentBottom: nil)
            }
            return $0.cached[wid] ?? BubbleObservation(visibility: .visible, contentBottom: nil)
        }
    }

    /// 同步读可见性状态（wake/telemetry 语义入口；障碍构造请用 observation(for:)）。
    func visibility(for wid: CGWindowID) -> BubbleVisibility {
        observation(for: wid).visibility
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
            s.identityDirty = true
        }
    }

    // MARK: - 默认捕获器（macOS 14+ ScreenCaptureKit，macOS 13/失败 → unavailable 保守 visible）

    private static let defaultMakeCapturer: BubbleCapturerFactory = {
        guard #available(macOS 14.0, *) else { return { _ in .unavailable } }
        guard let content = try? await SCShareableContent.excludingDesktopWindows(
            false, onScreenWindowsOnly: false) else {
            return { _ in .unavailable }
        }
        return { candidate in await captureStats(candidate, content: content) }
    }

    // MARK: - ScreenCaptureKit 捕获（static，后台执行）

    /// 计算降采样捕获尺寸（保持纵横比、最长边 ≤ downsampleMaxSide）；
    /// 面积未超 downsampleAreaThreshold 返回 nil（小窗不降采样，路径不变）。
    static func downsampleCaptureSize(width: Int, height: Int) -> (width: Int, height: Int)? {
        let area = Double(width) * Double(height)
        guard area > BubbleVisibilityThresholds.downsampleAreaThreshold else { return nil }
        let longest = Double(max(width, height))
        let scale = Double(BubbleVisibilityThresholds.downsampleMaxSide) / longest
        return (max(1, Int((Double(width) * scale).rounded())),
                max(1, Int((Double(height) * scale).rounded())))
    }

    /// 把降采样捕获的统计换算回原始窗口坐标：contentBottom 按行高比例放大
    ///（round(maxY * origH/capH)，随后的避让矩形仍受整窗高度 cap），
    /// nonTransparentPixelCount 按面积比例放大（count * origArea/capArea，用于阈值比较）。
    static func rescaleDownsampledStats(
        _ stats: BubbleAlphaStats,
        captureWidth: Int, captureHeight: Int,
        originalWidth: Int, originalHeight: Int
    ) -> BubbleAlphaStats {
        guard captureWidth > 0, captureHeight > 0, originalWidth > 0, originalHeight > 0 else {
            return stats
        }
        let rowScale = Double(originalHeight) / Double(captureHeight)
        let areaScale = (Double(originalWidth) * Double(originalHeight))
            / (Double(captureWidth) * Double(captureHeight))
        let contentBottom = stats.contentBottom >= 0
            ? Int((Double(stats.contentBottom) * rowScale).rounded()) : -1
        let count = Int((Double(stats.nonTransparentPixelCount) * areaScale).rounded())
        return BubbleAlphaStats(nonTransparentPixelCount: count, contentBottom: contentBottom)
    }

    @available(macOS 14.0, *)
    private static func captureStats(
        _ candidate: WinCandidate, content: SCShareableContent
    ) async -> BubbleCaptureOutcome {
        guard let win = content.windows.first(where: { $0.windowID == candidate.wid }) else {
            return .targetMissing
        }
        let filter = SCContentFilter(desktopIndependentWindow: win)
        let originalWidth = Int(candidate.bounds.width.rounded())
        let originalHeight = Int(candidate.bounds.height.rounded())
        let downsampled = downsampleCaptureSize(width: originalWidth, height: originalHeight)
        let config = SCStreamConfiguration()
        if let size = downsampled {
            config.width = size.width
            config.height = size.height
        } else {
            config.width = originalWidth
            config.height = originalHeight
        }
        config.scalesToFit = false
        config.showsCursor = false
        guard let img = try? await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config) else {
            return .unavailable
        }
        let captured = computeAlphaStats(image: img)
        guard let size = downsampled else { return .stats(captured) }
        return .stats(rescaleDownsampledStats(
            captured,
            captureWidth: size.width, captureHeight: size.height,
            originalWidth: originalWidth, originalHeight: originalHeight))
    }

    /// 内存计算 alpha 统计（不保存图/OCR/记录颜色文字）。static → 后台 Task 内执行。
    static func computeAlphaStats(image: CGImage) -> BubbleAlphaStats {
        let rep = NSBitmapImageRep(cgImage: image)
        let w = rep.pixelsWide, h = rep.pixelsHigh
        guard w > 0, h > 0 else { return BubbleAlphaStats(nonTransparentPixelCount: 0, contentBottom: -1) }
        var nonTrans = 0, maxY = -1
        for y in 0..<h {
            for x in 0..<w {
                guard let c = rep.colorAt(x: x, y: y) else { continue }
                if c.alphaComponent > 0.04 {
                    nonTrans += 1
                    if y > maxY { maxY = y }
                }
            }
        }
        return BubbleAlphaStats(nonTransparentPixelCount: nonTrans, contentBottom: maxY)
    }
}
