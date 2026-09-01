import Cocoa
import os
import QuartzCore

/// latest-only tick 门闩。display/timer beat 在 pending/running 时直接丢弃；
/// visibility wake 若恰在 tick 执行中到达，仅保留一次 follow-up，避免丢最终状态。
final class FollowTickCoalescer: @unchecked Sendable {
    typealias Enqueue = (DispatchWorkItem) -> Void

    private struct State {
        var pending = false
        var running = false
        var wakeDuringRun = false
        var stopped = false
    }

    private let lock = OSAllocatedUnfairLock(initialState: State())
    private let enqueue: Enqueue
    private let tick: () -> Void

    init(
        enqueue: @escaping Enqueue = { DispatchQueue.main.async(execute: $0) },
        tick: @escaping () -> Void
    ) {
        self.enqueue = enqueue
        self.tick = tick
    }

    func requestBeat() { request(keepIfRunning: false) }
    func requestWake() { request(keepIfRunning: true) }

    func stop() {
        lock.withLock {
            $0.stopped = true
            $0.pending = false
            $0.wakeDuringRun = false
        }
    }

    private func request(keepIfRunning: Bool) {
        let shouldEnqueue = lock.withLock { state -> Bool in
            guard !state.stopped else { return false }
            if state.running {
                if keepIfRunning { state.wakeDuringRun = true }
                return false
            }
            guard !state.pending else { return false }
            state.pending = true
            return true
        }
        if shouldEnqueue { enqueueDrain() }
    }

    private func enqueueDrain() {
        enqueue(DispatchWorkItem { [weak self] in self?.drain() })
    }

    private func drain() {
        let shouldRun = lock.withLock { state -> Bool in
            guard !state.stopped, state.pending else { return false }
            state.pending = false
            state.running = true
            return true
        }
        guard shouldRun else { return }

        tick()

        let shouldEnqueue = lock.withLock { state -> Bool in
            state.running = false
            guard !state.stopped, state.wakeDuringRun else {
                state.wakeDuringRun = false
                return false
            }
            state.wakeDuringRun = false
            state.pending = true
            return true
        }
        if shouldEnqueue { enqueueDrain() }
    }
}

protocol FollowTickTimer: AnyObject {
    func invalidate()
}

extension Timer: FollowTickTimer {}

protocol FollowDisplayLink: AnyObject {
    func add(to runLoop: RunLoop, forMode mode: RunLoop.Mode)
    func invalidate()
}

@available(macOS 14.0, *)
extension CADisplayLink: FollowDisplayLink {}

/// 运行时跟随调度器：moving 用 window-bound display link（macOS 14+），
/// macOS 13 用屏幕能力决定的 repeating Timer；stable/hidden 用低频 one-shot Timer。
/// 所有 source callback 只请求 coalesced tick，实际 tick 始终在主线程执行。
final class FollowTickScheduler: NSObject {
    typealias DisplayLinkFactory = (NSObject, Selector) -> FollowDisplayLink?
    typealias TimerFactory = (TimeInterval, Bool, @escaping () -> Void) -> FollowTickTimer

    private enum ActiveSource {
        case none
        case displayLink
        case repeatingTimer
        case oneShotTimer
    }

    private let runTick: () -> FollowState
    private let makeDisplayLink: DisplayLinkFactory
    private let canUseDisplayLink: () -> Bool
    private let maximumFramesPerSecond: () -> Int
    private let monotonicNow: () -> TimeInterval
    private let stableDelayHint: () -> TimeInterval?
    private let makeTimer: TimerFactory
    private var coalescer: FollowTickCoalescer!
    private var timer: FollowTickTimer?
    private var displayLink: FollowDisplayLink?
    private var movingWatchdog: FollowTickTimer?
    /// 本 moving episode 内 display link 已被 watchdog 判死：降级 repeating Timer 后
    /// 不再重建 link，避免逐拍 create/invalidate churn；离开 moving（stable/hidden）复位。
    private var movingLinkDegraded = false
    private var activeSource: ActiveSource = .none
    private var activeRepeatingFPS: Int?
    private var stopped = false

    init(
        runTick: @escaping () -> FollowState,
        makeDisplayLink: @escaping DisplayLinkFactory,
        canUseDisplayLink: @escaping () -> Bool,
        maximumFramesPerSecond: @escaping () -> Int,
        monotonicNow: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime },
        stableDelayHint: @escaping () -> TimeInterval? = { nil },
        makeTimer: @escaping TimerFactory = FollowTickScheduler.makeRunLoopTimer
    ) {
        self.runTick = runTick
        self.makeDisplayLink = makeDisplayLink
        self.canUseDisplayLink = canUseDisplayLink
        self.maximumFramesPerSecond = maximumFramesPerSecond
        self.monotonicNow = monotonicNow
        self.stableDelayHint = stableDelayHint
        self.makeTimer = makeTimer
        super.init()
        self.coalescer = FollowTickCoalescer { [weak self] in self?.performTick() }
    }

    var visibilityChangeCallback: @Sendable () -> Void {
        let gate = coalescer!
        return { gate.requestWake() }
    }

    /// 测试观测钩子：当前节拍源类型（不参与调度决策）。
    var isDisplayLinkActive: Bool { activeSource == .displayLink }
    var isRepeatingTimerActive: Bool { activeSource == .repeatingTimer }

    func requestWake() { coalescer.requestWake() }

    func start() {
        precondition(Thread.isMainThread)
        configure(for: .hidden, tickStartedAt: nil)
    }

    func stop() {
        precondition(Thread.isMainThread)
        guard !stopped else { return }
        stopped = true
        coalescer.stop()
        invalidateSources()
    }

    static func fallbackFramesPerSecond(screenMaximum: Int) -> Int {
        guard screenMaximum > 0 else { return 60 }
        return min(screenMaximum, 120)
    }

    /// moving display link 饿死保护：健康 60Hz link 每 ~16.7ms 一拍并逐拍重布 watchdog，
    /// 永不触发；超过该窗口无任何 tick（link 因窗口 orderOut / 屏参数变化 / 系统侧失效
    /// 而静默死亡）则降级 repeating Timer。仅 moving + display link 期间存在，stable/hidden
    /// 与静止路径零开销（保持空闲 0% CPU 成果）。
    static let movingWatchdogInterval: TimeInterval = 0.25

    private func performTick() {
        precondition(Thread.isMainThread)
        guard !stopped else { return }
        let tickStartedAt = monotonicNow()
        let nextState = runTick()
        guard !stopped else { return }
        configure(for: nextState, tickStartedAt: tickStartedAt, stableRetryAfter: stableDelayHint())
    }

    private func configure(
        for state: FollowState,
        tickStartedAt: TimeInterval?,
        stableRetryAfter: TimeInterval? = nil
    ) {
        switch state {
        case .moving:
            startMovingSourceIfNeeded()
        case .stable:
            movingLinkDegraded = false
            scheduleStableTick(firstAnchor: tickStartedAt, retryAfter: stableRetryAfter)
        case .hidden:
            movingLinkDegraded = false
            scheduleOneShot(after: Follower.hiddenInterval)
        }
    }

    private func startMovingSourceIfNeeded() {
        let wantsDisplayLink: Bool
        if #available(macOS 14.0, *) {
            wantsDisplayLink = canUseDisplayLink()
        } else {
            wantsDisplayLink = false
        }
        if activeSource == .displayLink && wantsDisplayLink {
            armMovingWatchdog()
            return
        }

        if #available(macOS 14.0, *), wantsDisplayLink, !movingLinkDegraded,
           let link = makeDisplayLink(self, #selector(displayLinkDidFire(_:))) {
            invalidateSources()
            link.add(to: .main, forMode: .common)
            displayLink = link
            activeSource = .displayLink
            armMovingWatchdog()
            return
        }

        startRepeatingFallbackTimer()
    }

    private func startRepeatingFallbackTimer() {
        let fps = Self.fallbackFramesPerSecond(screenMaximum: maximumFramesPerSecond())
        if activeSource == .repeatingTimer, activeRepeatingFPS == fps { return }
        invalidateSources()
        timer = makeTimer(1.0 / Double(fps), true) { [weak self] in
            self?.coalescer.requestBeat()
        }
        activeSource = .repeatingTimer
        activeRepeatingFPS = fps
    }

    private func armMovingWatchdog() {
        movingWatchdog?.invalidate()
        movingWatchdog = makeTimer(Self.movingWatchdogInterval, false) { [weak self] in
            self?.movingWatchdogFired()
        }
    }

    /// watchdog 到期仍无下一拍：display link 已静默死亡（panel 可见但系统不驱动回调，
    /// 或窗口生命周期事件后失效）。降级 repeating Timer 保住 moving 节拍，
    /// 避免唯一节拍源饿死（生产 P0：拖动宠物后底座完全不动）。
    private func movingWatchdogFired() {
        movingWatchdog = nil
        guard !stopped, activeSource == .displayLink else { return }
        movingLinkDegraded = true
        startRepeatingFallbackTimer()
    }

    private func scheduleStableTick(firstAnchor: TimeInterval?, retryAfter: TimeInterval?) {
        let now = monotonicNow()
        // stable 探测间隔恒 0.1s（R6：0.2s 退避封底的起步延迟用户实测不可接受，已撤销；
        // 枚举 onscreenOnly 瘦身后无需以延迟换功耗）。probe pendingRetryAt 取更早者。
        let interval = Follower.stableInterval
        let deadline = (firstAnchor ?? now) + interval
        let delay = min(deadline - now, retryAfter ?? .greatestFiniteMagnitude)
        guard delay > 0 else {
            invalidateSources()
            coalescer.requestWake()
            return
        }
        scheduleOneShot(after: delay)
    }

    private func scheduleOneShot(after interval: TimeInterval) {
        invalidateSources()
        timer = makeTimer(interval, false) { [weak self] in
            self?.coalescer.requestBeat()
        }
        activeSource = .oneShotTimer
    }

    private func invalidateSources() {
        timer?.invalidate()
        timer = nil
        displayLink?.invalidate()
        displayLink = nil
        movingWatchdog?.invalidate()
        movingWatchdog = nil
        activeSource = .none
        activeRepeatingFPS = nil
    }

    private static func makeRunLoopTimer(
        interval: TimeInterval,
        repeats: Bool,
        callback: @escaping () -> Void
    ) -> FollowTickTimer {
        let timer = Timer(timeInterval: interval, repeats: repeats) { _ in callback() }
        timer.tolerance = 0
        RunLoop.main.add(timer, forMode: .common)
        return timer
    }

    @available(macOS 14.0, *)
    @objc private func displayLinkDidFire(_ link: CADisplayLink) {
        coalescer.requestBeat()
    }
}

/// 单次生产布局链：当前候选分类 → 气泡探测/cache → 可见障碍 → frame sink。
/// 几何与 AppKit 副作用留给 sink；此处只保证 main 与测试走同一编排路径。
enum FollowLayoutPass {
    typealias FrameSink = (CGRect, [CGRect]) -> Bool

    static func placeDock(
        mascot: WinCandidate,
        candidates: [WinCandidate],
        bubbleProbe: BubbleVisibilityProbe,
        evidence: (any RuntimeEvidenceRecording)? = nil,
        frameSink: FrameSink
    ) -> Bool {
        let obstacles = PetTracker.obstaclesNear(mascot: mascot, candidates: candidates)
        let petMaxY = mascot.bounds.maxY
        let classified = obstacles.map { ($0, PetTracker.obstacleKind($0, petMaxY: petMaxY)) }
        bubbleProbe.probe(candidates: classified.compactMap { pair in
            pair.1 == .bubble || pair.1 == .compositionSurface ? pair.0 : nil
        })
        // Mascot 只走独立参考通道（同一 capturer、独立缓存/generation），不进入
        // 障碍候选集 —— 避免 knownWids/复位合同（回归 A）被改写。CS 内容底只从
        // 主导探测 observation(for:) 读取，禁止再送进参考通道二次捕获。
        let csCandidates = classified.filter { $0.1 == .compositionSurface }
        bubbleProbe.updateReferences([mascot])
        // 活层代表先于避让集构造裁决：非代表 CS 层不产生布局，防止死层幽灵矩形把
        // dock 推离真实内容底；单 CS 实例时该候选即代表。
        var rep: WinCandidate?
        if csCandidates.count == 1 { rep = csCandidates[0].0 }
        if csCandidates.count > 1,
           case .stats(let mascotStats) = bubbleProbe.referenceOutcome(for: mascot.wid),
           mascotStats.contentBottom >= 0 {
            let epsilon: CGFloat = 2                       // 脚底±1px 动画抖动容差
            let upperBound: CGFloat = 172                  // 覆盖按钮+展开卡向下延伸（现场 ~110px）
            let petFootAbs = mascot.bounds.minY + CGFloat(mascotStats.contentBottom + 1)
            struct LiveLayer { let candidate: WinCandidate; let bottomAbs: CGFloat }
            var liveLayers: [LiveLayer] = []
            for (candidate, _) in csCandidates {
                let observation = bubbleProbe.observation(for: candidate.wid)
                guard observation.visibility == .visible,
                      let contentBottom = observation.contentBottom, contentBottom >= 0 else { continue }
                let csBottomAbs = candidate.bounds.minY + CGFloat(contentBottom + 1)
                if csBottomAbs >= petFootAbs - epsilon && csBottomAbs <= petFootAbs + upperBound {
                    liveLayers.append(LiveLayer(candidate: candidate, bottomAbs: csBottomAbs))
                }
            }
            rep = liveLayers.min(by: { lhs, rhs in
                if lhs.bottomAbs != rhs.bottomAbs { return lhs.bottomAbs < rhs.bottomAbs }
                return lhs.candidate.wid < rhs.candidate.wid
            })?.candidate   // 未落入一致性窗口 → rep=nil：显式回退 Mascot 窗口底锚
        }
        let visibleBounds = classified.compactMap { pair -> CGRect? in
            // 非代表 CS 层不参与布局（死层残影不得把 dock 推离活层内容底）。
            if pair.1 == .compositionSurface, pair.0.wid != rep?.wid { return nil }
            if pair.1 == .control { return pair.0.bounds }
            let observation = bubbleProbe.observation(for: pair.0.wid)
            guard observation.visibility == .visible else { return nil }
            guard let contentBottom = observation.contentBottom else {
                return pair.1 == .compositionSurface ? nil : pair.0.bounds
            }
            return CGRect(x: pair.0.bounds.minX, y: pair.0.bounds.minY,
                          width: pair.0.bounds.width,
                          height: min(CGFloat(contentBottom + 1), pair.0.bounds.height))
        }
        if let evidence {
            // 证据计数沿用二元 bubble/control 通道口径，与标题通道引入前保持连续。
            let bubbleCount = classified.filter { $0.1 != .control }.count
            evidence.recordLayoutTick(
                bubbleObstacles: bubbleCount,
                controlObstacles: classified.count - bubbleCount,
                visibleObstacles: visibleBounds.count
            )
        }
        // 布局锚：活层代表 contentBottom 观察 → effectivePetMaxY；否则回退窗口底。口径与
        // 上方避让矩形同源（contentBottom+1），展开态不产生双重下移。
        var effectivePetMaxY = mascot.bounds.maxY
        if let rep {
            let observation = bubbleProbe.observation(for: rep.wid)
            if observation.visibility == .visible, let contentBottom = observation.contentBottom {
                effectivePetMaxY = max(mascot.bounds.minY,
                                       rep.bounds.minY + CGFloat(contentBottom + 1))
            }
        }
        // 水平居中仍按 Mascot 窗口（origin.x/width 不变）；仅高度随内容底收缩/延伸。
        let adjustedPet = CGRect(x: mascot.bounds.minX, y: mascot.bounds.minY,
                                 width: mascot.bounds.width,
                                 height: effectivePetMaxY - mascot.bounds.minY)
        return frameSink(adjustedPet, visibleBounds)
    }
}

/// 一次跟随 tick 的纯决策层：把「该执行什么编排动作」从AppDelegate.tick 的副作用中剥离，
/// 使核心编排（数据 pause/resume、UI show/hide、候选为空、dockVisible）可纯函数测试。
/// 输入为只读快照，输出为互斥的动作信号；不触碰 UI / 数据 / timer。
///
/// 与 `Follower.decide`（决定频率与 setFrame）互补：
/// - Follower.decide：宠物几何 → 跟随状态机（hidden/moving/stable）。
/// - FollowTickPlan：跟随结果 → 编排动作（数据探测、UI 可见性）。
struct FollowTickInput {
    /// 本 tick 宠物是否可见（来自 Follower.showDock）。
    let petVisible: Bool
    /// 上一 tick 的宠物可见性（边沿触发用）。
    let wasPetVisible: Bool
    /// 用户「显示/隐藏底座」开关（settings.dockVisible）。用户隐藏只关 UI，不影响数据探测。
    let dockVisible: Bool
}

/// 纯决策输出（互斥动作信号）。执行层（AppDelegate.tick）只消费这些信号。
struct FollowTickPlan: Equatable {
    /// 数据探测 resume（petVisible false→true 边沿）：触发 provider.resume + refreshData。
    let resumeData: Bool
    /// 数据探测 pause（petVisible true→false 边沿）：触发 provider.pause + stopDataRefresh。
    let pauseData: Bool
    /// UI 可见 = 宠物可见 && 用户可见。执行层据此渲染 + 显示底座/详情。
    let showUI: Bool
    /// UI 需隐藏（宠物不可见 或 用户隐藏）。执行层据此隐藏底座 + 关详情。
    let hideUI: Bool
    /// 宠物消失（petVisible==false）：执行层据此清静止锚点/lastWID/bubbleProbe。
    let petDisappeared: Bool
}

/// 跟随 tick 编排纯决策。
enum FollowTickPlanner {
    /// 首个宠物可见上升沿后的数据刷新延迟，避免与启动/首帧竞争 CPU。
    static func initialDataRefreshDelay(hasCompletedFirstRefresh: Bool) -> TimeInterval {
        hasCompletedFirstRefresh ? 0 : 5
    }

    /// 纯函数：根据快照决策编排动作。
    /// - 数据探测仅跟随宠物可见性（与用户是否隐藏 UI 解耦）。
    /// - UI 可见 = 宠物可见 && 用户可见；用户隐藏只关 UI，仍跟踪宠物。
    static func decide(input: FollowTickInput) -> FollowTickPlan {
        let resumeData = input.petVisible && !input.wasPetVisible     // false→true
        let pauseData = !input.petVisible && input.wasPetVisible      // true→false
        let showUI = input.petVisible && input.dockVisible
        return FollowTickPlan(
            resumeData: resumeData,
            pauseData: pauseData,
            showUI: showUI,
            hideUI: !showUI,
            petDisappeared: !input.petVisible
        )
    }

    /// 容器回退通道在消失分支的 reset 门控（2026-08-28 QA P0 修复）。
    /// 容器候选在场时，hidden tick 只表示「捕获在途或尚未被接受」——此时 reset 会递增
    /// generation 并作废每次在途捕获，通道永远无法产出首个观察（饥饿）；WID 重用/宿主
    /// 重启的身份失效已由 ContainerPetProbe 的 wid-change generation 语义承担。
    /// 因此仅当本 tick 无可行容器候选（容器真消失）才允许 reset。
    static func containerProbeReset(containerCandidatePresent: Bool) -> Bool {
        !containerCandidatePresent
    }
}

// MARK: - 宠物来源路由（R2/R3：strong Mascot → 容器 → 仅无容器时 generic → none）

/// 一次 tick 的唯一宠物来源。生产 AppDelegate.tick 与测试必须消费同一结果，
/// 不在各自分支里重复排序优先级。
enum PetSourceRoute {
    /// 主通道窗口：strong Mascot（走 FollowLayoutPass 气泡/控件/CS 链路），或无容器
    /// 候选时保留的 generic 小窗口回退（旧宿主无 Mascot title 的兼容路径）。
    case primary(WinCandidate)
    /// 容器候选在场 → 容器通道；宠物矩形由 ContainerPetProbe 的已接受观察决定，
    /// 尚未接受时保持 hidden 等待既有 observation callback 唤醒（不允许临时窗口接管）。
    case container(WinCandidate)
    /// 无可行来源 → 隐藏底座。
    case none

    /// 诊断标签（匿名枚举名，不含 wid/PID/title/坐标）。
    var label: String {
        switch self {
        case .primary: return "primary"
        case .container: return "container"
        case .none: return "none"
        }
    }
}

/// 单一宠物来源解析器：候选快照 → 本 tick 唯一宠物来源。
/// 右键菜单、子菜单等与宠物无关的临时窗口只会出现在 generic 几何回退里；容器候选
/// 在场时它们既不能成为宠物矩形，也不能污染 lastWID 滞回（消费方按 route 写 lastWID）。
enum PetSourceRouter {
    static func resolve(
        primary: SelectionResult,
        containerCandidate: WinCandidate?
    ) -> PetSourceRoute {
        // 1. strong primary：独立 Mascot 身份永远优先（R1 主通道回归保护）。
        if primary.source == .strongMascot, let window = primary.selected {
            return .primary(window)
        }
        // 2. 容器候选在场 → 容器通道（R2/R3）：generic 几何回退（含临时菜单）不得接管。
        if let container = containerCandidate {
            return .container(container)
        }
        // 3. 仅无容器候选时保留 generic 回退（旧宿主无 Mascot title 的兼容路径）。
        if primary.source == .genericWindow, let window = primary.selected {
            return .primary(window)
        }
        return .none
    }
}
