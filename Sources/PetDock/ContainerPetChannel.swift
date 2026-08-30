import Cocoa
import CoreImage
import CoreMedia
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
    /// 捕获验证门限：非透明像素占比 ≤ 此值才算“近乎全透明的宠物容器”。QA-run-4 实测
    /// channel-active 值在 0.0090–0.0102 抖动（精灵抗锯齿/动画），旧 0.01 会造成通道
    /// 时有时无；正常不透明应用窗 >10× 该值，0.02 headroom 保留拒绝能力。
    static let opaqueFractionGate: Double = 0.02
    /// 合成宠物矩形边长合理范围（映射后 sanity）。
    static let petMinSide: CGFloat = 20
    static let petMaxSide: CGFloat = 400
    /// 稳态捕获节奏（rect 未变化）：3Hz 心跳；R7 要求内容边沿检测 p95 ≤ 0.4s，
    /// 同时保留低频捕获（而非 display link）的稳态 CPU 轮廓。
    static let stableCaptureInterval: TimeInterval = 0.33
    /// bbox 变化后的快速节奏（窗内内容移动跟随）。
    static let movingCaptureInterval: TimeInterval = 0.1
    /// bbox 变化后快速节奏的保持时长。
    static let movingHoldDuration: TimeInterval = 2.0
    /// 捕获降采样最长边上限（镜像 BubbleVisibility 降采样模式，无 bubble 阈值耦合）。
    static let downsampleMaxSide: CGFloat = 400
    /// managed SCStream 的最小帧间隔（3 fps；由系统按帧推送，替代固定成本很高的一次性截图轮询）。
    static let streamFrameInterval: TimeInterval = 0.33
    /// 首帧 watchdog：active 后 2s 内没有任何 frame 则按启动失败退役（只检查 first frame）。
    static let streamFirstFrameTimeout: TimeInterval = 2.0
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
        let scaleX = containerBounds.width / CGFloat(captureWidth)
        let scaleY = containerBounds.height / CGFloat(captureHeight)
        let width = CGFloat(stats.maxX - stats.minX + 1) * scaleX
        let height = CGFloat(stats.maxY - stats.minY + 1) * scaleY
        guard width >= ContainerPetHeuristics.petMinSide,
              width <= ContainerPetHeuristics.petMaxSide,
              height >= ContainerPetHeuristics.petMinSide,
              height <= ContainerPetHeuristics.petMaxSide else { return nil }
        return CGRect(
            x: containerBounds.minX + CGFloat(stats.minX) * scaleX,
            y: containerBounds.minY + CGFloat(stats.minY) * scaleY,
            width: width,
            height: height)
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

/// 像素捕获器接口（@Sendable 闭包，后台 Task 安全传递）；size = 降采样目标尺寸。
typealias ContainerCapturer = @Sendable (WinCandidate, CGSize) async -> ContainerCaptureOutcome

/// managed SCStream 的最小生命周期接口；具体 SCStream 生命周期由默认包装器持有。
protocol ContainerFrameStream: AnyObject, Sendable {
    func start() async throws
    func stop() async
}

/// frame 生产者与 probe 之间的消费合同：bbox 计算前先取 latest-wins token，
/// 计算完成后只交付一次 outcome，并立刻归还 token（期间新帧必须丢弃）。
protocol ContainerFrameConsumer: AnyObject, Sendable {
    func beginProcessing(_ streamEpoch: Int) -> ContainerFrameToken?
    func endProcessing()
    func deliver(_ outcome: ContainerCaptureOutcome, token: ContainerFrameToken) async
    /// SCStream didStopWithError 的专用生命周期入口；不得经过 frame-token gate。
    func streamDidTerminate(_ stream: any ContainerFrameStream) async
}

/// factory 在后台创建/启动 stream；candidate+size 是启动时的目标签名，consumer 是 probe。
typealias ContainerFrameStreamFactory = @Sendable (
    WinCandidate, CGSize, Int, any ContainerFrameConsumer
) async throws -> any ContainerFrameStream

struct ContainerFrameToken: Sendable {
    let streamEpoch: Int
}

/// 测试/运行时捕获 transport：macOS14+ 用 managed stream；显式 oneShot 供旧路径测试。
/// macOS 13: managed channel unavailable by design（SCScreenshotManager 一次性路径是 macOS14+ API，
/// 不虚构不可用的“legacy fallback”）。
enum ContainerCaptureTransport {
    case managedStream(factory: ContainerFrameStreamFactory?)
    case oneShot
}

/// 容器窗像素探测：镜像 BubbleVisibilityProbe 结构（锁保护状态、single-flight、
/// Task.detached 后台捕获、generation 失效语义）。
/// - 缓存保存**捕获坐标 bbox**（ContainerAlphaStats），每次 locate 用**当前** containerBounds
///   重新映射 → 容器整窗平移无需重新捕获即可即时跟随；快速节奏（0.1s）只留给窗内内容移动。
/// - accepted observation rect 相对上次交付结果变化时触发一次 onObservationChanged
///   （none→rect / rect→different）；reset() / wid 变化清空 baseline 重新武装。
final class ContainerPetProbe: Sendable {
    private static let streamHealthLogger = PetLogger()

    internal struct ProbeState: Sendable {
        /// 最近一次**通过门限**的捕获统计（捕获像素坐标 bbox）；nil = 尚无有效观察。
        var cached: ContainerAlphaStats?
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
        /// stream frame 映射/门限判定所用的最近候选 bounds；每次 locate 刷新。
        var currentContainerBounds: CGRect?
    }

    internal struct StreamRuntimeState: Sendable {
        var active: (any ContainerFrameStream)?
        var activeWID: CGWindowID?
        var starting = false
        var stopping = false
        var frameComputing = false
        /// Start-attempt identity. Allocated before factory completion so frames that land
        /// during starting can be associated with the future active stream.
        var streamEpoch = 0
        /// The epoch whose deadline is currently armed; nil means no watchdog is armed.
        var armedEpoch: Int?
        /// The epoch of the latest accepted stats outcome (identity-safe cancellation input).
        var acceptedFrameEpoch: Int?
        var firstFrameDelivered = false
        var firstFrameDeadline: TimeInterval?
        var consecutiveStartFailures = 0
        var nextStartAllowedAt: TimeInterval?
        var startingGeneration = 0
        var startingWID: CGWindowID?
        var processingGeneration = 0
        var processingWID: CGWindowID?
        var processingBounds: CGRect?
        var processingEpoch = 0
    }

    internal let lock: OSAllocatedUnfairLock<ProbeState>
    internal let streamRuntime = OSAllocatedUnfairLock<StreamRuntimeState>(initialState: StreamRuntimeState())
    private let monotonicNow: @Sendable () -> TimeInterval
    private let canCapture: @Sendable () -> Bool
    private let capturer: ContainerCapturer
    private let transport: ContainerCaptureTransport
    private let streamFactory: ContainerFrameStreamFactory?
    private let usesManagedStream: Bool
    private let onObservationChanged: (@Sendable () -> Void)?
    private let onStreamStartFailure: (@Sendable () -> Void)?

    init(monotonicNow: @escaping @Sendable () -> TimeInterval = { ProcessInfo.processInfo.systemUptime },
         canCapture: @escaping @Sendable () -> Bool = { CGPreflightScreenCaptureAccess() },
         capturer: ContainerCapturer? = nil,
         transport: ContainerCaptureTransport = .oneShot,
         onObservationChanged: (@Sendable () -> Void)? = nil,
         onStreamStartFailure: (@Sendable () -> Void)? = nil) {
        self.lock = OSAllocatedUnfairLock(initialState: ProbeState())
        self.monotonicNow = monotonicNow
        self.canCapture = canCapture
        self.capturer = capturer ?? Self.defaultCapturer
        self.transport = transport
        switch transport {
        case .managedStream(let factory):
            self.usesManagedStream = true
            self.streamFactory = factory ?? Self.defaultStreamFactory
        case .oneShot:
            self.usesManagedStream = false
            self.streamFactory = nil
        }
        self.onObservationChanged = onObservationChanged
        self.onStreamStartFailure = onStreamStartFailure
    }

    deinit {
        shutdown()
    }

    // MARK: - 主线程接口（tick 同步调用）

    /// tick 主线程同步调用。返回当前合成宠物矩形（用**当前** containerBounds 映射）；
    /// 权限缺失 → .unavailable 并丢弃陈旧缓存；wid 变化 → 清缓存（新 episode）；
    /// macOS14+ managed transport 只负责启动唯一 stream，帧由后台 queue 推送。
    /// 显式 oneShot transport 保留旧路径语义与测试注入。
    func locate(container: WinCandidate) -> ContainerPetOutcome {
        // WID 切换先退役旧 stream，避免 runtime state 仍看到 active old-WID 而不启动新目标。
        let knownWID = lock.withLock { $0.knownWID }
        if let knownWID, knownWID != container.wid {
            stopActiveStream()
            streamRuntime.withLock { s in
                s.consecutiveStartFailures = 0
                s.nextStartAllowedAt = nil
            }
        }
        guard canCapture() else {
            // 权限/能力不可用：陈旧缓存必须丢弃（stale WID 不得降级为错误锚点），
            // 旧在途结果经 generation 失效；inFlight 由旧 Task 自清（strict single-flight）。
            lock.withLock { s in
                if s.cached != nil || s.lastDeliveredRect != nil || s.inFlight || s.knownWID != nil {
                    s.generation += 1
                    s.cached = nil
                    s.knownWID = nil
                    s.lastDeliveredRect = nil
                    s.currentContainerBounds = nil
                    s.movingUntil = -.greatestFiniteMagnitude
                }
            }
            stopActiveStream()
            return .unavailable
        }
        let time = monotonicNow()
        let managedStreamAvailable: Bool
        if #available(macOS 14.0, *) {
            managedStreamAvailable = true
        } else {
            managedStreamAvailable = false
        }
        if usesManagedStream && !managedStreamAvailable {
            // macOS 13: managed channel unavailable by design；不得伪造 WID/cache/stream 状态。
            return .unavailable
        }
        let useManagedStream = usesManagedStream && managedStreamAvailable
        if useManagedStream {
            // watchdog 是 locate 驱动的单调 deadline 检查：无 steady-state timer 成本。
            retireFirstFrameTimeoutIfDue(now: time)
        }
        struct CaptureStart: Sendable {
            let generation: Int
            let container: WinCandidate
            let captureSize: CGSize
        }
        let start: CaptureStart?
        let outcome: ContainerPetOutcome
        (start, outcome) = lock.withLock { s -> (CaptureStart?, ContainerPetOutcome) in
            // wid 变化（宿主重启 / WID 重用）：清缓存 + 新 episode + generation++（旧结果作废）。
            if let known = s.knownWID, known != container.wid {
                s.generation += 1
                s.cached = nil
                s.lastDeliveredRect = nil
                s.currentContainerBounds = nil
                s.movingUntil = -.greatestFiniteMagnitude
            }
            s.knownWID = container.wid
            s.currentContainerBounds = container.bounds
            // 缓存按当前 containerBounds 现映射：整窗平移即时跟随，不依赖下一次捕获。
            var result = ContainerPetOutcome.empty
            if let cached = s.cached,
               let rect = ContainerPetChannel.mapToPetRect(
                    stats: cached,
                    captureWidth: cached.captureWidth,
                    captureHeight: cached.captureHeight,
                    containerBounds: container.bounds) {
                result = .bounds(rect)
            }
            guard !s.inFlight else { return (nil, result) }   // one-shot single-flight
            let interval: TimeInterval
            if useManagedStream {
                // 此分支不会走 one-shot；放在同一 switch 中避免 managed/legacy cadence 混用。
                interval = ContainerPetHeuristics.stableCaptureInterval
            } else if time < s.movingUntil {
                interval = ContainerPetHeuristics.movingCaptureInterval
            } else {
                interval = ContainerPetHeuristics.stableCaptureInterval
            }
            guard time - s.lastCaptureAt >= interval else { return (nil, result) }
            s.inFlight = true
            s.lastCaptureAt = time
            let target = ContainerPetChannel.captureSize(
                width: Int(container.bounds.width.rounded()),
                height: Int(container.bounds.height.rounded()))
                .map { CGSize(width: $0.width, height: $0.height) }
                ?? CGSize(width: container.bounds.width, height: container.bounds.height)
            return (CaptureStart(generation: s.generation, container: container, captureSize: target), result)
        }
        if useManagedStream {
            startStreamIfNeeded(container: container)
            return outcome
        }
        guard let start else { return outcome }
        let cap = capturer
        let lock = self.lock
        let notify = onObservationChanged
        let now = monotonicNow
        let gen = start.generation
        let wid = start.container.wid
        let scheduledBounds = start.container.bounds
        let target = start.captureSize
        let scheduled = start.container
        // Task.detached：不捕获 self（仅捕获 Sendable 局部值）→ 像素统计在后台线程执行。
        Task.detached {
            let result = await cap(scheduled, target)
            let shouldNotify: Bool = lock.withLock { s in
                s.inFlight = false   // 旧 Task 始终清自己的在途 token
                // generation / wid 校验：reset 或容器切换后到达的旧结果绝不写缓存。
                guard s.generation == gen, s.knownWID == wid else { return false }
                // 捕获验证门限：stats 且映射有效（按调度时 bounds 判定）才成为观察；
                // targetMissing / unavailable / 超门限 → 保守保留旧有效观察，不触发。
                guard case .stats(let stats) = result,
                      let observationRect = ContainerPetChannel.mapToPetRect(
                        stats: stats,
                        captureWidth: stats.captureWidth,
                        captureHeight: stats.captureHeight,
                        containerBounds: scheduledBounds) else { return false }
                if let old = s.cached, old != stats {
                    // bbox（含捕获尺寸）变化 → 快速节奏保持窗口。
                    s.movingUntil = now() + ContainerPetHeuristics.movingHoldDuration
                }
                s.cached = stats
                let changed = s.lastDeliveredRect != observationRect
                s.lastDeliveredRect = observationRect
                return changed
            }
            if shouldNotify { notify?() }
        }
        return outcome
    }

    /// 诊断用：当前是否已有有效观察缓存（不暴露任何内容）。
    func hasObservation() -> Bool {
        lock.withLock { $0.cached != nil }
    }

    /// 宠物/容器消失路径（tick hidden 分支）调用：清缓存 + 新 episode；generation++ 使旧在途
    /// 结果作废，并停止 live stream。不设 inFlight=false（旧 Task 自清，strict single-flight）。
    func reset() {
        lock.withLock { s in
            s.generation += 1
            s.cached = nil
            s.knownWID = nil
            s.lastDeliveredRect = nil
            s.currentContainerBounds = nil
            s.movingUntil = -.greatestFiniteMagnitude
        }
        streamRuntime.withLock { s in
            s.consecutiveStartFailures = 0
            s.nextStartAllowedAt = nil
        }
        stopActiveStream()
    }

    /// app quit / 显式停机：停止唯一 live stream；重复调用是安全的 no-op。
    func shutdown() {
        stopActiveStream()
    }

    // MARK: - managed stream lifecycle（QA-run-4 capture pivot）

    private func startStreamIfNeeded(container: WinCandidate) {
        guard usesManagedStream, streamFactory != nil else { return }
        guard #available(macOS 14.0, *) else { return }
        let now = monotonicNow()
        let startGeneration = lock.withLock { $0.generation }
        let shouldStart = streamRuntime.withLock { s -> (Bool, Int)? in
            guard !s.starting, !s.stopping, s.active == nil, s.activeWID == nil,
                  s.nextStartAllowedAt == nil || now >= s.nextStartAllowedAt! else {
                return nil
            }
            s.streamEpoch += 1
            let streamEpoch = s.streamEpoch
            s.armedEpoch = nil
            s.acceptedFrameEpoch = nil
            s.firstFrameDelivered = false
            s.firstFrameDeadline = nil
            s.starting = true
            s.startingGeneration = startGeneration
            s.startingWID = container.wid
            return (true, streamEpoch)
        }
        guard let (shouldStart, streamEpoch) = shouldStart, shouldStart,
              let factory = streamFactory else { return }
        Self.streamHealthLogger.log("container stream start attempt epoch=\(streamEpoch)")
        let target = ContainerPetChannel.captureSize(
            width: Int(container.bounds.width.rounded()),
            height: Int(container.bounds.height.rounded()))
            .map { CGSize(width: $0.width, height: $0.height) }
            ?? CGSize(width: container.bounds.width, height: container.bounds.height)
        let consumer: any ContainerFrameConsumer = self
        let runtimeLock = streamRuntime
        let probeLock = lock
        let nowProvider = monotonicNow
        let firstFrameTimeout = ContainerPetHeuristics.streamFirstFrameTimeout
        let scheduled = container
        // Snapshot probe identity before taking runtimeLock; nested probe reads create an
        // avoidable lock-ordering hazard on the completion task.
        let activationContext = probeLock.withLock {
            (generation: $0.generation, knownWID: $0.knownWID)
        }
        Task.detached(priority: .utility) {
            do {
                let stream = try await factory(scheduled, target, streamEpoch, consumer)
                // factory 返回时必须在同一把 runtime 锁下复查停机/切换竞态；
                // stopping=true 的新 stream 绝不能进入 active。
                // Activation also rechecks whether this exact epoch already delivered an
                // accepted frame while starting; it must never overwrite that cancellation.
                let accepted = runtimeLock.withLock { s -> Bool in
                    guard s.starting, !s.stopping, s.active == nil,
                          s.startingGeneration == activationContext.generation,
                          s.startingWID == scheduled.wid,
                          activationContext.knownWID == scheduled.wid else {
                        return false
                    }
                    s.active = stream
                    s.activeWID = scheduled.wid
                    s.starting = false
                    let frameAlreadyAccepted = s.acceptedFrameEpoch == s.streamEpoch
                    if frameAlreadyAccepted {
                        s.armedEpoch = nil
                        s.firstFrameDelivered = true
                        s.firstFrameDeadline = nil
                        s.consecutiveStartFailures = 0
                        s.nextStartAllowedAt = nil
                        Self.streamHealthLogger.log(
                            "container stream first frame accepted epoch=\(s.streamEpoch)")
                    } else {
                        s.armedEpoch = s.streamEpoch
                        s.firstFrameDelivered = false
                        s.firstFrameDeadline = nowProvider() + firstFrameTimeout
                    }
                    return true
                }
                if !accepted {
                    runtimeLock.withLock { $0.starting = false }
                    await stream.stop()
                    runtimeLock.withLock { $0.stopping = false }
                }
            } catch {
                let errorContext = probeLock.withLock {
                    (generation: $0.generation, knownWID: $0.knownWID)
                }
                let (shouldDeliverUnavailable, shouldRecordFailure) = runtimeLock.withLock { s -> (Bool, Bool) in
                    let wasStopping = s.stopping
                    s.starting = false
                    s.stopping = false
                    let attemptStillCurrent = errorContext.knownWID == scheduled.wid
                        && errorContext.generation == s.startingGeneration
                        && !wasStopping
                    if attemptStillCurrent {
                        s.consecutiveStartFailures += 1
                        s.nextStartAllowedAt = nowProvider() + Self.startFailureBackoff(
                            consecutiveFailures: s.consecutiveStartFailures)
                    }
                    return (attemptStillCurrent, attemptStillCurrent)
                }
                if shouldRecordFailure {
                    let reason: String
                    if case ContainerStreamError.targetMissing = error {
                        reason = "target-missing"
                    } else if case ContainerStreamError.unavailable = error {
                        reason = "enumeration-unavailable"
                    } else {
                        reason = "factory-or-start-error"
                    }
                    Self.streamHealthLogger.log(
                        "container stream start failure epoch=\(streamEpoch) reason=\(reason)")
                    self.onStreamStartFailure?()
                }
                if shouldDeliverUnavailable {
                    await consumer.deliver(
                        .unavailable,
                        token: ContainerFrameToken(streamEpoch: streamEpoch))
                }
            }
        }
    }

    private func stopActiveStream() {
        let stream = streamRuntime.withLock { s -> (any ContainerFrameStream)? in
            if let active = s.active {
                s.active = nil
                s.activeWID = nil
                s.stopping = true
                s.armedEpoch = nil
                return active
            }
            if s.starting {
                // factory/start 仍在途；factory 完成路径在同一锁下看到 stopping 并退役新 stream。
                s.stopping = true
            }
            return nil
        }
        guard let stream else { return }
        Self.streamHealthLogger.log("container stream retirement reason=explicit")
        let runtimeLock = streamRuntime
        Task.detached(priority: .utility) {
            await stream.stop()
            runtimeLock.withLock { $0.stopping = false }
        }
    }

    /// stream completion 和 one-shot completion 共用的 accepted-observation 输入端；
    /// edge/baseline/generation/WID 门限与 telemetry 触发完全一致。
    private func processStreamOutcome(
        _ result: ContainerCaptureOutcome,
        token: ContainerFrameToken
    ) async {
        // Frames-are-truth：mid-stream stall 不做 watchdog 退役；静态窗口可能稀疏送帧，
        // observation cache 负责 retention。只有“从未收到首帧”的启动路径被健康检查。
        let frameContext = streamRuntime.withLock { s -> (Int, CGWindowID?, CGRect?, Int)? in
            guard s.frameComputing else { return nil }
            return (s.processingGeneration, s.processingWID, s.processingBounds, s.streamEpoch)
        }
        guard let (generation, wid, bounds, currentEpoch) = frameContext,
              currentEpoch == token.streamEpoch else { return }
        let (shouldNotify, acceptedStats): (Bool, Bool) = lock.withLock { s in
            // beginProcessing 已捕获 generation/WID/bounds；reset/WID 切换会使旧 frame 失效。
            // token.streamEpoch 是回调 source identity；stale source 帧整体 DROP。
            guard let bounds,
                  s.generation == generation,
                  s.knownWID == wid else { return (false, false) }
            guard case .stats(let stats) = result,
                  let observationRect = ContainerPetChannel.mapToPetRect(
                    stats: stats,
                    captureWidth: stats.captureWidth,
                    captureHeight: stats.captureHeight,
                    containerBounds: bounds) else { return (false, false) }
            if let old = s.cached, old != stats {
                s.movingUntil = monotonicNow() + ContainerPetHeuristics.movingHoldDuration
            }
            s.cached = stats
            let changed = s.lastDeliveredRect != observationRect
            s.lastDeliveredRect = observationRect
            return (changed, true)
        }
        // Token identity is the stream's source epoch, never runtime's current epoch. A stale
        // queued callback may take the latest-wins token after replacement activation, but it
        // can neither feed observation state nor cancel/satisfy replacement health.
        if acceptedStats {
            let firstFrameAcceptedNow = streamRuntime.withLock { s -> Bool in
                s.acceptedFrameEpoch = token.streamEpoch
                guard s.armedEpoch == token.streamEpoch, !s.firstFrameDelivered else { return false }
                s.firstFrameDelivered = true
                s.firstFrameDeadline = nil
                s.consecutiveStartFailures = 0
                s.nextStartAllowedAt = nil
                return true
            }
            if firstFrameAcceptedNow {
                Self.streamHealthLogger.log(
                    "container stream first frame accepted epoch=\(token.streamEpoch)")
            }
        }
        if shouldNotify { onObservationChanged?() }
    }

    /// didStopWithError 专用入口：不受 frame-token gate 限制。按 identity 退役该 stream；
    /// unavailable 不擦除既有有效 cache（与 capture-unavailable retention 语义一致），但
    /// 必须 wake，让下一次 tick 在 runtime 已空后启动干净 replacement。
    private func processStreamTermination(_ stream: any ContainerFrameStream) async {
        let shouldNotify = streamRuntime.withLock { s -> Bool in
            guard let active = s.active,
                  ObjectIdentifier(active) == ObjectIdentifier(stream),
                  s.activeWID != nil else { return false }
            s.active = nil
            s.activeWID = nil
            s.armedEpoch = nil
            s.starting = false
            s.stopping = false
            s.firstFrameDelivered = false
            s.firstFrameDeadline = nil
            return true
            }
        if shouldNotify {
            Self.streamHealthLogger.log("container stream retirement reason=didStop")
        }
        if shouldNotify { onObservationChanged?() }
    }

    /// 连续 first-frame 失败的 2s -> 4s -> 8s 退避；cap 后维持 8s。
    private static func startFailureBackoff(consecutiveFailures: Int) -> TimeInterval {
        let schedule: [TimeInterval] = [2, 4, 8]
        let index = min(max(consecutiveFailures, 1) - 1, schedule.count - 1)
        return schedule[index]
    }

    /// active stream 超过 deadline 仍未送帧：走 wrapper.stop 的 didStop-equivalent teardown，
    /// 记录脱敏 start failure，退避后由下一次 locate 干净重启。不得杀 mid-stream stall。
    private func retireFirstFrameTimeoutIfDue(now: TimeInterval) {
        let retired = streamRuntime.withLock { s -> (any ContainerFrameStream)? in
            guard let active = s.active,
                  s.activeWID != nil,
                  !s.starting,
                  !s.stopping,
                  let armedEpoch = s.armedEpoch,
                  armedEpoch == s.streamEpoch,
                  !s.firstFrameDelivered,
                  let deadline = s.firstFrameDeadline,
                  now >= deadline else {
                return nil
            }
            s.active = nil
            s.activeWID = nil
            s.armedEpoch = nil
            s.starting = false
            s.stopping = true
            s.firstFrameDelivered = false
            s.firstFrameDeadline = nil
            s.consecutiveStartFailures += 1
            s.nextStartAllowedAt = now + Self.startFailureBackoff(
                consecutiveFailures: s.consecutiveStartFailures)
            return active
        }
        guard let stream = retired else { return }
        Self.streamHealthLogger.log("container stream first-frame timeout; retiring stream")
        onStreamStartFailure?()
        let runtimeLock = streamRuntime
        let notify = onObservationChanged
        Task.detached(priority: .utility) {
            await stream.stop()
            runtimeLock.withLock { $0.stopping = false }
            notify?()
        }
    }

    // MARK: - 默认捕获器（macOS 14+ ScreenCaptureKit；每轮捕获一次共享清单枚举）

    private static let defaultCapturer: ContainerCapturer = { candidate, size in
        guard #available(macOS 14.0, *) else {
            return .unavailable
        }
        guard let content = try? await SCShareableContent.excludingDesktopWindows(
            false, onScreenWindowsOnly: true) else {
            return .unavailable
        }
        return await captureStats(candidate, size: size, content: content)
    }

    @available(macOS 14.0, *)
    private static func captureStats(
        _ candidate: WinCandidate, size: CGSize, content: SCShareableContent
    ) async -> ContainerCaptureOutcome {
        guard let win = content.windows.first(where: { $0.windowID == candidate.wid }) else {
            return .targetMissing
        }
        let filter = SCContentFilter(desktopIndependentWindow: win)
        let config = SCStreamConfiguration()
        config.width = max(1, Int(size.width.rounded()))
        config.height = max(1, Int(size.height.rounded()))
        config.scalesToFit = false
        config.showsCursor = false
        guard let img = try? await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config) else {
            return .unavailable
        }
        return .stats(ContainerPetChannel.computeOpaqueBBox(image: img))
    }

    private static let defaultStreamFactory: ContainerFrameStreamFactory = { candidate, size, streamEpoch, consumer in
        guard #available(macOS 14.0, *) else {
            throw ContainerStreamError.unsupportedOS
        }
        let stream = try await ContainerSCFrameStream.make(
            candidate: candidate, size: size, streamEpoch: streamEpoch, consumer: consumer)
        try await stream.start()
        return stream
    }
}

extension ContainerPetProbe: ContainerFrameConsumer {
    func beginProcessing(_ sourceEpoch: Int) -> ContainerFrameToken? {
        let context = lock.withLock { s -> (Int, CGWindowID, CGRect)? in
            guard let wid = s.knownWID, let bounds = s.currentContainerBounds else { return nil }
            return (s.generation, wid, bounds)
        }
        return streamRuntime.withLock { s -> ContainerFrameToken? in
            guard !s.frameComputing else { return nil }
            guard let (generation, wid, bounds) = context else { return nil }
            let token = ContainerFrameToken(streamEpoch: sourceEpoch)
            s.frameComputing = true
            s.processingGeneration = generation
            s.processingWID = wid
            s.processingBounds = bounds
            s.processingEpoch = token.streamEpoch
            // Token acquisition only snapshots identity; accepted-stats completion owns
            // watchdog cancellation so non-stats outcomes cannot invalidate health state.
            return token
        }
    }

    func endProcessing() {
        streamRuntime.withLock { $0.frameComputing = false }
    }

    func deliver(_ outcome: ContainerCaptureOutcome, token: ContainerFrameToken) async {
        await processStreamOutcome(outcome, token: token)
    }

    func streamDidTerminate(_ stream: any ContainerFrameStream) async {
        await processStreamTermination(stream)
    }
}

enum ContainerStreamError: Error {
    case unsupportedOS
    case targetMissing
    case unavailable
}

/// 默认 ScreenCaptureKit stream：3fps 帧推送；bbox 在后台计算，期间新帧 latest-wins 丢弃。
@available(macOS 14.0, *)
private final class ContainerSCFrameStream: NSObject, ContainerFrameStream, SCStreamOutput, @unchecked Sendable {
    private static let imageContext = CIContext(options: [.cacheIntermediates: false])
    private static let stopFailureLogger = PetLogger()

    private let stream: SCStream
    private let outputQueue = DispatchQueue(label: "petdock.container-pet.frames", qos: .utility)
    private weak var consumer: (any ContainerFrameConsumer)?
    private let streamEpoch: Int

    private init(stream: SCStream, streamEpoch: Int, consumer: any ContainerFrameConsumer) {
        self.stream = stream
        self.streamEpoch = streamEpoch
        self.consumer = consumer
        super.init()
    }

    static func make(
        candidate: WinCandidate,
        size: CGSize,
        streamEpoch: Int,
        consumer: any ContainerFrameConsumer
    ) async throws -> ContainerSCFrameStream {
        // Fresh enumeration is part of every start attempt. SCShareableContent, SCWindow,
        // and SCContentFilter are deliberately scoped to this call; no failed attempt is reused.
        guard let content = try? await SCShareableContent.excludingDesktopWindows(
            false, onScreenWindowsOnly: true) else {
            throw ContainerStreamError.unavailable
        }
        guard let window = content.windows.first(where: { $0.windowID == candidate.wid }) else {
            throw ContainerStreamError.targetMissing
        }
        let configuration = SCStreamConfiguration()
        configuration.width = max(1, Int(size.width.rounded()))
        configuration.height = max(1, Int(size.height.rounded()))
        configuration.scalesToFit = false
        configuration.showsCursor = false
        configuration.minimumFrameInterval = CMTime(
            seconds: ContainerPetHeuristics.streamFrameInterval,
            preferredTimescale: 600)
        configuration.queueDepth = 3
        let stopProxy = ContainerSCFrameStreamStopProxy(consumer: consumer)
        let scStream = SCStream(
            filter: SCContentFilter(desktopIndependentWindow: window),
            configuration: configuration,
            delegate: stopProxy)
        let wrapper = ContainerSCFrameStream(
            stream: scStream, streamEpoch: streamEpoch, consumer: consumer)
        stopProxy.attach(stream: wrapper)
        return wrapper
    }

    func start() async throws {
        try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: outputQueue)
        try await stream.startCapture()
    }

    func stop() async {
        // 先移除 output，确保即使 stopCapture 抛错也不会继续投递帧；调用方已在 runtime lock
        // 下提前 retire active，因此 stop 失败仍允许下一次 locate 干净重启。
        try? stream.removeStreamOutput(self, type: .screen)
        do {
            try await stream.stopCapture()
        } catch {
            Self.stopFailureLogger.log("container stream stop failed: \(String(describing: error))")
        }
    }

    func stream(
        _ stream: SCStream,
        didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
        of type: SCStreamOutputType
    ) {
        guard type == .screen,
              sampleBuffer.isValid,
              CMSampleBufferGetNumSamples(sampleBuffer) == 1,
              let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let image = CIImage(cvPixelBuffer: pixelBuffer)
        guard let cgImage = Self.imageContext.createCGImage(image, from: image.extent),
              let consumer else { return }
        // 取 token 在回调线程；bbox 在 detached utility task。token 未归还时后续帧直接 DROP。
        guard let token = consumer.beginProcessing(streamEpoch) else { return }
        Task.detached(priority: .utility) { [consumer, token] in
            let outcome = ContainerCaptureOutcome.stats(
                ContainerPetChannel.computeOpaqueBBox(image: cgImage))
            await consumer.deliver(outcome, token: token)
            consumer.endProcessing()
        }
    }
}

/// SCStream 的 delegate 入口必须独立于 output wrapper；proxy 只把异常停机转换为保守 unavailable。
@available(macOS 14.0, *)
private final class ContainerSCFrameStreamStopProxy: NSObject, SCStreamDelegate, @unchecked Sendable {
    private weak var consumer: (any ContainerFrameConsumer)?
    private weak var stream: (any ContainerFrameStream)?

    init(consumer: any ContainerFrameConsumer) {
        self.consumer = consumer
        super.init()
    }

    func attach(stream: any ContainerFrameStream) {
        self.stream = stream
    }

    func stream(_ scStream: SCStream, didStopWithError error: Error) {
        guard let consumer, let frameStream = self.stream else { return }
        Task.detached(priority: .utility) {
            await consumer.streamDidTerminate(frameStream)
        }
    }
}
