import Cocoa
import os
import ScreenCaptureKit

// MARK: - 容器宠物通道（宿主 overlay 容器窗内像素 alpha 定位；主 Mascot 通道的回退）

/// 隐私合同与 BubbleVisibility 一致：只在**内存**计算匿名 alpha 像素统计（非透明像素数 +
/// bbox），不 OCR、不保存图像、不记录颜色 / 文字 / 内容。宿主 2026-08-28 更新后宠物不再有
/// 独立 Mascot 窗口，而是绘制在一个巨大、近乎全透明（实测非透明占比 ~0.19%）的宿主 overlay
/// 容器窗（layer 3，约 772x2549）内；对该容器捕获取唯一不透明 bbox 即可恢复宠物位置，合成
/// 矩形喂给既有 Follower / FollowTickPlan / DockPanel 管线（不另起状态机）。

/// 容器通道阈值：集中一处（镜像 PetHeuristics），宿主再次改版时只调这里。
enum ContainerPetHeuristics {
    /// 容器窗 layer 下限（实测宿主 overlay 容器 layer=3；主窗 layer=0 本就被排除）。
    static let minLayer = 2
    /// 容器窗面积下限（实测 ~772x2549 约等于 1.97M；旧结构 Composition Surface 768x912 约 0.7M
    /// 不满足 → 主 Mascot 通道存在时容器通道绝不干扰）。
    static let minArea: CGFloat = 1_000_000
    /// 捕获验证门限：QA 实测容器帧在 0.0090–0.0102 间抖动；0.02 留出抗锯齿余量，
    /// 同时与几何签名共同防止无关大内容窗劫持跟踪。
    static let opaqueFractionGate: Double = 0.02
    /// 合成宠物矩形边长合理范围（映射后 sanity）。
    static let petMinSide: CGFloat = 20
    static let petMaxSide: CGFloat = 400
    /// 稳态捕获节奏：用户选择 option 1 的约 3Hz；稳态轮次由区域裁剪控制 CPU。
    static let stableCaptureInterval: TimeInterval = 0.33
    /// bbox 变化后的快速节奏（窗内内容移动跟随）。
    static let movingCaptureInterval: TimeInterval = 0.1
    /// bbox 变化后快速节奏的保持时长。
    static let movingHoldDuration: TimeInterval = 2.0
    /// 捕获降采样最长边上限（镜像 BubbleVisibility 降采样模式，无 bubble 阈值耦合）。
    static let downsampleMaxSide: CGFloat = 400
    /// 区域追踪向左右及上方留出的移动余量。
    static let regionHorizontalMargin: CGFloat = 150
    static let regionTopMargin: CGFloat = 150
    /// 下方包含 bubbleHeightMax（约 223px）及额外移动余量。
    static let regionBelowMargin: CGFloat = 400
}

/// 容器窗选择：纯函数签名，只用可观测窗口事实（不依赖标题）。
enum ContainerPetSelector {
    /// 全部通过几何签名的候选（面积最大优先；并列 wid 较小者在前）。
    /// 签名：onscreen + 非主窗 + layer ≥ minLayer + area ≥ minArea；
    /// 捕获验证门限（非透明占比）由 ContainerPetProbe 在捕获完成时承担。
    static func matches(candidates: [WinCandidate]) -> [WinCandidate] {
        candidates
            .filter {
                $0.isOnscreen
                    && !$0.isLikelyMainWindow
                    && $0.layer >= ContainerPetHeuristics.minLayer
                    && $0.area >= ContainerPetHeuristics.minArea
            }
            .sorted { lhs, rhs in
                if lhs.area != rhs.area { return lhs.area > rhs.area }
                return lhs.wid < rhs.wid
            }
    }

    /// 唯一容器候选：面积最大者（并列取 wid 较小者，确定性）。
    static func selectContainer(candidates: [WinCandidate]) -> WinCandidate? {
        matches(candidates: candidates).first
    }
}

/// 匿名像素 alpha 统计（捕获像素坐标 bbox；隐私合同同 BubbleAlphaStats）。
/// 无非透明像素时 nonTransparentPixelCount=0 且 bbox 各字段为 -1。
struct ContainerAlphaStats: Equatable, Sendable {
    let nonTransparentPixelCount: Int   // alpha>0.04 像素数
    let minX: Int
    let minY: Int
    let maxX: Int
    let maxY: Int
    let captureWidth: Int
    let captureHeight: Int
}

/// ScreenCaptureKit 观察结果语义（对应 BubbleCaptureOutcome）。
/// - stats：成功取得目标窗口并完成匿名 alpha 统计。
/// - targetMissing：成功取得窗口清单，但目标 WID 不在清单中。
/// - unavailable：权限、清单、截图或统计不可用；必须保守处理（不改写既有缓存）。
enum ContainerCaptureOutcome: Equatable, Sendable {
    case stats(ContainerAlphaStats)
    case targetMissing
    case unavailable
}

/// 单次截图轮次：首次定位使用全窗；稳定态使用窗口本地（左上原点）的追踪区域。
enum ContainerCaptureRound: Equatable, Sendable {
    case fullWindow
    case region(CGRect)
}

struct ContainerCaptureRequest: Equatable, Sendable {
    let round: ContainerCaptureRound
    let outputSize: CGSize
}

/// locate() 同步返回：缓存的合成宠物矩形 / 尚无有效观察 / 捕获不可用（权限缺失，已清陈旧缓存）。
enum ContainerPetOutcome: Equatable, Sendable {
    case bounds(CGRect)
    case empty
    case unavailable
}

/// 纯统计 / 映射（无状态，便于单测）。
enum ContainerPetChannel {
    /// 计算降采样捕获尺寸（保持纵横比、最长边 ≤ downsampleMaxSide）；
    /// 最长边未超上限返回 nil（无需降采样）。
    static func captureSize(width: Int, height: Int) -> (width: Int, height: Int)? {
        let longest = max(width, height)
        guard longest > Int(ContainerPetHeuristics.downsampleMaxSide) else { return nil }
        let scale = Double(ContainerPetHeuristics.downsampleMaxSide) / Double(longest)
        return (max(1, Int((Double(width) * scale).rounded())),
                max(1, Int((Double(height) * scale).rounded())))
    }

    /// alpha bbox 映射到窗口本地坐标。实机 full/region 对照确认 x/y 与 sourceRect 同向；
    /// 先前失败来自跨屏窗口的 sourceRect 原点，不是图像 Y 翻转。
    static func windowBBox(stats: ContainerAlphaStats, captureRegion: CGRect) -> CGRect? {
        guard stats.captureWidth > 0, stats.captureHeight > 0,
              stats.nonTransparentPixelCount > 0,
              stats.minX >= 0, stats.minY >= 0,
              stats.maxX >= stats.minX, stats.maxY >= stats.minY,
              stats.maxX < stats.captureWidth, stats.maxY < stats.captureHeight,
              captureRegion.width > 0, captureRegion.height > 0 else { return nil }
        let scaleX = captureRegion.width / CGFloat(stats.captureWidth)
        let scaleY = captureRegion.height / CGFloat(stats.captureHeight)
        return CGRect(
            x: captureRegion.minX + CGFloat(stats.minX) * scaleX,
            y: captureRegion.minY + CGFloat(stats.minY) * scaleY,
            width: CGFloat(stats.maxX - stats.minX + 1) * scaleX,
            height: CGFloat(stats.maxY - stats.minY + 1) * scaleY)
    }

    /// 把捕获时窗口本地 bbox 映射到当前 CGWindowList bounds；窗口平移无需等待下一轮截图。
    static func mapWindowBBoxToPetRect(
        windowBBox: CGRect,
        capturedWindowSize: CGSize,
        containerBounds: CGRect
    ) -> CGRect? {
        guard capturedWindowSize.width > 0, capturedWindowSize.height > 0,
              containerBounds.width > 0, containerBounds.height > 0 else { return nil }
        let scaleX = containerBounds.width / capturedWindowSize.width
        let scaleY = containerBounds.height / capturedWindowSize.height
        let rect = CGRect(
            x: containerBounds.minX + windowBBox.minX * scaleX,
            y: containerBounds.minY + windowBBox.minY * scaleY,
            width: windowBBox.width * scaleX,
            height: windowBBox.height * scaleY)
        guard rect.width >= ContainerPetHeuristics.petMinSide,
              rect.width <= ContainerPetHeuristics.petMaxSide,
              rect.height >= ContainerPetHeuristics.petMinSide,
              rect.height <= ContainerPetHeuristics.petMaxSide else { return nil }
        return rect
    }

    /// 最近 bbox 周围的裁剪区域；下方 400px 明确保留气泡区域。
    static func trackedRegion(for windowBBox: CGRect, windowSize: CGSize) -> CGRect {
        let expanded = CGRect(
            x: windowBBox.minX - ContainerPetHeuristics.regionHorizontalMargin,
            y: windowBBox.minY - ContainerPetHeuristics.regionTopMargin,
            width: windowBBox.width + ContainerPetHeuristics.regionHorizontalMargin * 2,
            height: windowBBox.height + ContainerPetHeuristics.regionTopMargin
                + ContainerPetHeuristics.regionBelowMargin)
        return expanded.intersection(CGRect(origin: .zero, size: windowSize))
    }

    static func bboxTouchesCaptureEdge(_ stats: ContainerAlphaStats) -> Bool {
        stats.nonTransparentPixelCount > 0
            && (stats.minX == 0 || stats.minY == 0
                || stats.maxX == stats.captureWidth - 1
                || stats.maxY == stats.captureHeight - 1)
    }

    /// 区域降采样会产生约一个源像素的量化误差；交付边沿与 moving 判定沿用位置容差。
    static func rectMateriallyChanged(
        _ lhs: CGRect?, _ rhs: CGRect, tolerance: CGFloat
    ) -> Bool {
        guard let lhs else { return true }
        if abs(lhs.width - rhs.width) > tolerance
            || abs(lhs.height - rhs.height) > tolerance { return true }
        let dx = lhs.minX - rhs.minX
        let dy = lhs.minY - rhs.minY
        return (dx * dx + dy * dy).squareRoot() > tolerance
    }

    /// 区域可能跨显示器；按 tracked region 的全局相交面积选择实际承载内容的显示器。
    static func captureDisplayBounds(
        windowRegion: CGRect, containerBounds: CGRect, displayBounds: [CGRect]
    ) -> CGRect? {
        let globalRegion = windowRegion.offsetBy(
            dx: containerBounds.minX, dy: containerBounds.minY)
        guard let selected = displayBounds.max(by: { lhs, rhs in
            let lhsIntersection = globalRegion.intersection(lhs)
            let rhsIntersection = globalRegion.intersection(rhs)
            let lhsArea = lhsIntersection.isNull ? 0 : lhsIntersection.width * lhsIntersection.height
            let rhsArea = rhsIntersection.isNull ? 0 : rhsIntersection.width * rhsIntersection.height
            return lhsArea < rhsArea
        }) else { return nil }
        let intersection = globalRegion.intersection(selected)
        guard !intersection.isNull, intersection.width > 0, intersection.height > 0 else { return nil }
        return selected
    }

    /// 实机 sweep 校准：跨屏 desktopIndependentWindow 的 sourceRect 原点是“容器窗与所选
    /// 显示器交集”的左上角，而不是整个容器窗原点或 filter.contentRect 全局原点。
    static func sourceRect(
        windowRegion: CGRect, containerBounds: CGRect, displayBounds: CGRect
    ) -> CGRect {
        let displaySegment = containerBounds.intersection(displayBounds)
        let segmentOriginInWindow = CGPoint(
            x: displaySegment.minX - containerBounds.minX,
            y: displaySegment.minY - containerBounds.minY)
        return windowRegion.offsetBy(
            dx: -segmentOriginInWindow.x,
            dy: -segmentOriginInWindow.y)
    }

    /// 区域轮次沿用全窗的降采样比例，避免裁剪后反而把小区域放大到 400px。
    static func captureOutputSize(windowSize: CGSize, captureRegion: CGRect) -> CGSize {
        let longest = max(windowSize.width, windowSize.height)
        let scale = longest > ContainerPetHeuristics.downsampleMaxSide
            ? ContainerPetHeuristics.downsampleMaxSide / longest
            : 1
        return CGSize(
            width: max(1, (captureRegion.width * scale).rounded()),
            height: max(1, (captureRegion.height * scale).rounded()))
    }

    /// 捕获 bbox → 全局 Quartz 宠物矩形。containerBounds（CGWindowList bounds）是唯一
    /// 权威的 origin/size 来源：探测期 SCWindow.frame 与 CG bounds 存在 ~50px 偏差，混用
    /// 两个来源会引入系统性漂移（PRD 风险项）。
    /// 门限：非透明占比 ≤ opaqueFractionGate 且映射宽高 ∈ [petMinSide, petMaxSide]；
    /// 无非透明像素 / 超门限 / 退化输入 / 单像素 bbox（映射后低于 petMinSide）→ nil。
    static func mapToPetRect(
        stats: ContainerAlphaStats,
        captureWidth: Int,
        captureHeight: Int,
        containerBounds: CGRect
    ) -> CGRect? {
        guard captureWidth > 0, captureHeight > 0,
              stats.nonTransparentPixelCount > 0,
              stats.minX >= 0, stats.minY >= 0,
              stats.maxX >= stats.minX, stats.maxY >= stats.minY,
              containerBounds.width > 0, containerBounds.height > 0 else { return nil }
        let fraction = Double(stats.nonTransparentPixelCount)
            / (Double(captureWidth) * Double(captureHeight))
        guard fraction <= ContainerPetHeuristics.opaqueFractionGate else { return nil }
        guard stats.captureWidth == captureWidth, stats.captureHeight == captureHeight,
              let windowBBox = windowBBox(
                stats: stats,
                captureRegion: CGRect(
                    origin: .zero,
                    size: CGSize(width: containerBounds.width, height: containerBounds.height))) else {
            return nil
        }
        return mapWindowBBoxToPetRect(
            windowBBox: windowBBox,
            capturedWindowSize: containerBounds.size,
            containerBounds: containerBounds)
    }

    /// 内存计算全图 alpha 统计（全 bbox，alpha>0.04 阈值与 BubbleVisibility.computeAlphaStats
    /// 一致）。static → 后台 Task 内执行；不保存图 / 不 OCR / 不记录颜色文字。
    static func computeOpaqueBBox(image: CGImage) -> ContainerAlphaStats {
        let rep = NSBitmapImageRep(cgImage: image)
        let w = rep.pixelsWide, h = rep.pixelsHigh
        guard w > 0, h > 0 else {
            return ContainerAlphaStats(nonTransparentPixelCount: 0, minX: -1, minY: -1, maxX: -1, maxY: -1,
                                       captureWidth: w, captureHeight: h)
        }
        var count = 0, minX = Int.max, minY = Int.max, maxX = -1, maxY = -1
        for y in 0..<h {
            for x in 0..<w {
                guard let c = rep.colorAt(x: x, y: y) else { continue }
                if c.alphaComponent > 0.04 {
                    count += 1
                    if x < minX { minX = x }
                    if x > maxX { maxX = x }
                    if y < minY { minY = y }
                    if y > maxY { maxY = y }
                }
            }
        }
        if count == 0 { minX = -1; minY = -1 }
        return ContainerAlphaStats(nonTransparentPixelCount: count, minX: minX, minY: minY,
                                   maxX: maxX, maxY: maxY, captureWidth: w, captureHeight: h)
    }
}

/// 像素捕获器接口（@Sendable 闭包，后台 Task 安全传递）。
typealias ContainerCapturer = @Sendable (WinCandidate, ContainerCaptureRequest) async -> ContainerCaptureOutcome

/// 容器窗像素探测：镜像 BubbleVisibilityProbe 结构（锁保护状态、single-flight、
/// Task.detached 后台捕获、generation 失效语义）。
/// - 缓存保存**捕获坐标 bbox**（ContainerAlphaStats），每次 locate 用**当前** containerBounds
///   重新映射 → 容器整窗平移无需重新捕获即可即时跟随；快速节奏（0.1s）只留给窗内内容移动。
/// - accepted observation rect 相对上次交付结果变化时触发一次 onObservationChanged
///   （none→rect / rect→different）；reset() / wid 变化清空 baseline 重新武装。
final class ContainerPetProbe: Sendable {
    /// PetLogger 在 release 默认关闭，仅 `--verbose` 或 DEBUG 下记录匿名生命周期事件。
    private static let captureLogger = PetLogger()

    internal struct ProbeState: Sendable {
        /// 最近一次**通过门限**的捕获统计（捕获像素坐标 bbox）；nil = 尚无有效观察。
        var cached: ContainerAlphaStats?
        /// cached 对应的窗口本地捕获区域及捕获时整窗尺寸。
        var cachedCaptureRegion: CGRect?
        var cachedWindowSize: CGSize?
        /// 下一轮 region capture 的窗口本地区域；nil 表示尚未完成全窗定位。
        var regionTracking: CGRect?
        /// true 时下一轮必须全窗定位（首次/reset/WID变化/region miss/贴边）。
        var needsFullLocate = true
        /// 已知容器 wid（首次 locate 后锁定；wid 变化 → 清缓存 + 新 episode，防 WID 重用串台）。
        var knownWID: CGWindowID?
        var lastCaptureAt: TimeInterval = -.greatestFiniteMagnitude
        var inFlight = false
        /// bbox 变化后快速节奏保持到此时刻（单调时钟；初始值表示从未移动）。
        var movingUntil: TimeInterval = -.greatestFiniteMagnitude
        /// 候选切换 / reset 递增；旧 Task 回调 generation 不匹配时丢弃。
        var generation = 0
        /// 上次已交付给回调的 observation rect；nil = baseline 未武装（下次有效 rect 触发边沿）。
        var lastDeliveredRect: CGRect?
    }

    internal let lock: OSAllocatedUnfairLock<ProbeState>
    private let monotonicNow: @Sendable () -> TimeInterval
    private let canCapture: @Sendable () -> Bool
    private let capturer: ContainerCapturer
    private let onObservationChanged: (@Sendable () -> Void)?

    init(monotonicNow: @escaping @Sendable () -> TimeInterval = { ProcessInfo.processInfo.systemUptime },
         canCapture: @escaping @Sendable () -> Bool = { CGPreflightScreenCaptureAccess() },
         capturer: ContainerCapturer? = nil,
         onObservationChanged: (@Sendable () -> Void)? = nil) {
        self.lock = OSAllocatedUnfairLock(initialState: ProbeState())
        self.monotonicNow = monotonicNow
        self.canCapture = canCapture
        self.capturer = capturer ?? Self.defaultCapturer
        self.onObservationChanged = onObservationChanged
    }

    // MARK: - 主线程接口（tick 同步调用）

    /// tick 主线程同步调用。返回当前合成宠物矩形（用**当前** containerBounds 映射）；
    /// 权限缺失 → .unavailable 并丢弃陈旧缓存；wid 变化 → 清缓存（新 episode）；
    /// 节拍允许时调度单飞后台捕获（稳态 0.33s / bbox 变化后 0.1s 保持 movingHoldDuration）。
    func locate(container: WinCandidate) -> ContainerPetOutcome {
        guard canCapture() else {
            // 权限/能力不可用：陈旧缓存必须丢弃（stale WID 不得降级为错误锚点），
            // 旧在途结果经 generation 失效；inFlight 由旧 Task 自清（strict single-flight）。
            lock.withLock { s in
                if s.cached != nil || s.lastDeliveredRect != nil || s.inFlight || s.knownWID != nil {
                    s.generation += 1
                    s.cached = nil
                    s.cachedCaptureRegion = nil
                    s.cachedWindowSize = nil
                    s.regionTracking = nil
                    s.needsFullLocate = true
                    s.knownWID = nil
                    s.lastDeliveredRect = nil
                    s.movingUntil = -.greatestFiniteMagnitude
                }
            }
            return .unavailable
        }
        let time = monotonicNow()
        struct CaptureStart: Sendable {
            let generation: Int
            let container: WinCandidate
            let request: ContainerCaptureRequest
        }
        let start: CaptureStart?
        let outcome: ContainerPetOutcome
        (start, outcome) = lock.withLock { s -> (CaptureStart?, ContainerPetOutcome) in
            // wid 变化（宿主重启 / WID 重用）：清缓存 + 新 episode + generation++（旧结果作废）。
            if let known = s.knownWID, known != container.wid {
                s.generation += 1
                s.cached = nil
                s.cachedCaptureRegion = nil
                s.cachedWindowSize = nil
                s.regionTracking = nil
                s.needsFullLocate = true
                s.lastDeliveredRect = nil
                s.movingUntil = -.greatestFiniteMagnitude
            }
            s.knownWID = container.wid
            // 缓存按当前 containerBounds 现映射：整窗平移即时跟随，不依赖下一次捕获。
            var result = ContainerPetOutcome.empty
            if let cached = s.cached,
               let captureRegion = s.cachedCaptureRegion,
               let capturedWindowSize = s.cachedWindowSize,
               let windowBBox = ContainerPetChannel.windowBBox(
                    stats: cached, captureRegion: captureRegion),
               let rect = ContainerPetChannel.mapWindowBBoxToPetRect(
                    windowBBox: windowBBox,
                    capturedWindowSize: capturedWindowSize,
                    containerBounds: container.bounds) {
                result = .bounds(rect)
            }
            guard !s.inFlight else { return (nil, result) }   // single-flight
            let interval = time < s.movingUntil
                ? ContainerPetHeuristics.movingCaptureInterval
                : ContainerPetHeuristics.stableCaptureInterval
            guard time - s.lastCaptureAt + 1e-9 >= interval else { return (nil, result) }
            s.inFlight = true
            s.lastCaptureAt = time
            let round: ContainerCaptureRound
            let captureRegion: CGRect
            if !s.needsFullLocate, let region = s.regionTracking {
                round = .region(region)
                captureRegion = region
            } else {
                round = .fullWindow
                captureRegion = CGRect(origin: .zero, size: container.bounds.size)
            }
            let target = ContainerPetChannel.captureOutputSize(
                windowSize: container.bounds.size, captureRegion: captureRegion)
            let request = ContainerCaptureRequest(round: round, outputSize: target)
            return (CaptureStart(generation: s.generation, container: container, request: request), result)
        }
        guard let start else { return outcome }
        let cap = capturer
        let lock = self.lock
        let notify = onObservationChanged
        let now = monotonicNow
        let gen = start.generation
        let wid = start.container.wid
        let scheduledBounds = start.container.bounds
        let request = start.request
        let scheduled = start.container
        Self.captureLogger.log("container capture start attempt")
        // Task.detached：不捕获 self（仅捕获 Sendable 局部值）→ 像素统计在后台线程执行。
        Task.detached {
            let result = await cap(scheduled, request)
            let completion = lock.withLock { s -> (
                shouldNotify: Bool, firstObservation: Bool, failureReason: String?
            ) in
                s.inFlight = false   // 旧 Task 始终清自己的在途 token
                // generation / wid 校验：reset 或容器切换后到达的旧结果绝不写缓存。
                guard s.generation == gen, s.knownWID == wid else {
                    return (false, false, nil)
                }
                // 捕获验证门限：stats 且映射有效（按调度时 bounds 判定）才成为观察；
                // targetMissing / unavailable / 超门限 → 保守保留旧有效观察，不触发。
                let stats: ContainerAlphaStats
                switch result {
                case .stats(let value):
                    stats = value
                case .targetMissing:
                    s.needsFullLocate = true
                    return (false, false, "target-missing")
                case .unavailable:
                    s.needsFullLocate = true
                    return (false, false, "unavailable")
                }
                let expectedWidth = max(1, Int(request.outputSize.width.rounded()))
                let expectedHeight = max(1, Int(request.outputSize.height.rounded()))
                guard stats.captureWidth == expectedWidth,
                      stats.captureHeight == expectedHeight else {
                    s.needsFullLocate = true
                    return (false, false, "capture-size")
                }
                let captureRegion: CGRect
                var needsFullLocateAfterAcceptance = false
                switch request.round {
                case .fullWindow:
                    captureRegion = CGRect(origin: .zero, size: scheduledBounds.size)
                    let fraction = Double(stats.nonTransparentPixelCount)
                        / (Double(stats.captureWidth) * Double(stats.captureHeight))
                    guard stats.nonTransparentPixelCount > 0,
                          fraction <= ContainerPetHeuristics.opaqueFractionGate else {
                        s.needsFullLocate = true
                        return (false, false, "validation")
                    }
                case .region(let region):
                    captureRegion = region
                    guard stats.nonTransparentPixelCount > 0 else {
                        s.needsFullLocate = true
                        return (false, false, "region-empty")
                    }
                    needsFullLocateAfterAcceptance = ContainerPetChannel.bboxTouchesCaptureEdge(stats)
                }
                guard let windowBBox = ContainerPetChannel.windowBBox(
                        stats: stats, captureRegion: captureRegion),
                      let observationRect = ContainerPetChannel.mapWindowBBoxToPetRect(
                        windowBBox: windowBBox,
                        capturedWindowSize: scheduledBounds.size,
                        containerBounds: scheduledBounds) else {
                    s.needsFullLocate = true
                    return (false, false, "validation")
                }
                let firstObservation = s.cached == nil
                let quantizationTolerance = max(
                    captureRegion.width / CGFloat(stats.captureWidth),
                    captureRegion.height / CGFloat(stats.captureHeight)) + 1e-9
                let oldWindowBBox: CGRect? = {
                    guard let old = s.cached, let oldRegion = s.cachedCaptureRegion else { return nil }
                    return ContainerPetChannel.windowBBox(stats: old, captureRegion: oldRegion)
                }()
                if ContainerPetChannel.rectMateriallyChanged(
                    oldWindowBBox, windowBBox, tolerance: quantizationTolerance) {
                    // bbox（含捕获尺寸）变化 → 快速节奏保持窗口。
                    s.movingUntil = now() + ContainerPetHeuristics.movingHoldDuration
                }
                s.cached = stats
                s.cachedCaptureRegion = captureRegion
                s.cachedWindowSize = scheduledBounds.size
                s.regionTracking = ContainerPetChannel.trackedRegion(
                    for: windowBBox, windowSize: scheduledBounds.size)
                s.needsFullLocate = needsFullLocateAfterAcceptance
                let changed = ContainerPetChannel.rectMateriallyChanged(
                    s.lastDeliveredRect, observationRect, tolerance: quantizationTolerance)
                if changed { s.lastDeliveredRect = observationRect }
                return (changed, firstObservation, nil)
            }
            if let reason = completion.failureReason {
                Self.captureLogger.log("container capture failure reason=\(reason)")
            }
            if completion.firstObservation {
                Self.captureLogger.log("container capture first observation")
            }
            if completion.shouldNotify { notify?() }
        }
        return outcome
    }

    /// 诊断用：当前是否已有有效观察缓存（不暴露任何内容）。
    func hasObservation() -> Bool {
        lock.withLock { $0.cached != nil }
    }

    /// 宠物/容器消失路径（tick hidden 分支）调用：清缓存 + 新 episode；generation++ 使旧在途
    /// 结果作废。不设 inFlight=false（旧 Task 自清，strict single-flight 同 BubbleVisibilityProbe）。
    func reset() {
        lock.withLock { s in
            s.generation += 1
            s.cached = nil
            s.cachedCaptureRegion = nil
            s.cachedWindowSize = nil
            s.regionTracking = nil
            s.needsFullLocate = true
            s.knownWID = nil
            s.lastDeliveredRect = nil
            s.movingUntil = -.greatestFiniteMagnitude
        }
    }

    // MARK: - 默认捕获器（macOS 14+ ScreenCaptureKit；每轮捕获一次共享清单枚举）

    private static let defaultCapturer: ContainerCapturer = { candidate, request in
        guard #available(macOS 14.0, *) else { return .unavailable }
        guard let content = try? await SCShareableContent.excludingDesktopWindows(
            false, onScreenWindowsOnly: true) else {
            return .unavailable
        }
        return await captureStats(candidate, request: request, content: content)
    }

    @available(macOS 14.0, *)
    private static func captureStats(
        _ candidate: WinCandidate, request: ContainerCaptureRequest, content: SCShareableContent
    ) async -> ContainerCaptureOutcome {
        guard let win = content.windows.first(where: { $0.windowID == candidate.wid }) else {
            return .targetMissing
        }
        let filter = SCContentFilter(desktopIndependentWindow: win)
        let config = SCStreamConfiguration()
        config.width = max(1, Int(request.outputSize.width.rounded()))
        config.height = max(1, Int(request.outputSize.height.rounded()))
        config.scalesToFit = false
        config.showsCursor = false
        if case .region(let windowRegion) = request.round {
            var displayCount: UInt32 = 0
            var displayIDs = [CGDirectDisplayID](repeating: 0, count: 16)
            guard CGGetActiveDisplayList(UInt32(displayIDs.count), &displayIDs, &displayCount) == .success,
                  displayCount > 0 else { return .unavailable }
            let bounds = displayIDs.prefix(Int(displayCount)).map(CGDisplayBounds)
            guard let displayBounds = ContainerPetChannel.captureDisplayBounds(
                windowRegion: windowRegion,
                containerBounds: candidate.bounds,
                displayBounds: bounds) else { return .unavailable }
            let sourceRect = ContainerPetChannel.sourceRect(
                windowRegion: windowRegion,
                containerBounds: candidate.bounds,
                displayBounds: displayBounds)
            let displaySegment = candidate.bounds.intersection(displayBounds)
            guard sourceRect.minX >= 0, sourceRect.minY >= 0,
                  sourceRect.maxX <= displaySegment.width,
                  sourceRect.maxY <= displaySegment.height else { return .unavailable }
            config.sourceRect = sourceRect
        }
        guard let img = try? await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config) else {
            return .unavailable
        }
        return .stats(ContainerPetChannel.computeOpaqueBBox(image: img))
    }
}
