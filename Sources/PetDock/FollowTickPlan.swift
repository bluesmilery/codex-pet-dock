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

/// 运行时跟随调度器：moving 用 window-bound display link（macOS 14+），
/// macOS 13 用屏幕能力决定的 repeating Timer；stable/hidden 用低频 one-shot Timer。
/// 所有 source callback 只请求 coalesced tick，实际 tick 始终在主线程执行。
final class FollowTickScheduler: NSObject {
    typealias DisplayLinkFactory = (NSObject, Selector) -> AnyObject?

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
    private var coalescer: FollowTickCoalescer!
    private var timer: Timer?
    private var displayLink: AnyObject?
    private var activeSource: ActiveSource = .none
    private var stopped = false

    init(
        runTick: @escaping () -> FollowState,
        makeDisplayLink: @escaping DisplayLinkFactory,
        canUseDisplayLink: @escaping () -> Bool,
        maximumFramesPerSecond: @escaping () -> Int
    ) {
        self.runTick = runTick
        self.makeDisplayLink = makeDisplayLink
        self.canUseDisplayLink = canUseDisplayLink
        self.maximumFramesPerSecond = maximumFramesPerSecond
        super.init()
        self.coalescer = FollowTickCoalescer { [weak self] in self?.performTick() }
    }

    var visibilityChangeCallback: @Sendable () -> Void {
        let gate = coalescer!
        return { gate.requestWake() }
    }

    func requestWake() { coalescer.requestWake() }

    func start() {
        precondition(Thread.isMainThread)
        configure(for: .hidden)
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

    private func performTick() {
        precondition(Thread.isMainThread)
        guard !stopped else { return }
        let nextState = runTick()
        guard !stopped else { return }
        configure(for: nextState)
    }

    private func configure(for state: FollowState) {
        switch state {
        case .moving:
            startMovingSourceIfNeeded()
        case .stable:
            scheduleOneShot(after: Follower.stableInterval)
        case .hidden:
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
        if (activeSource == .displayLink && wantsDisplayLink)
            || (activeSource == .repeatingTimer && !wantsDisplayLink) { return }
        invalidateSources()

        if #available(macOS 14.0, *), wantsDisplayLink,
           let link = makeDisplayLink(self, #selector(displayLinkDidFire(_:))) as? CADisplayLink {
            link.add(to: .main, forMode: .common)
            displayLink = link
            activeSource = .displayLink
            return
        }

        let fps = Self.fallbackFramesPerSecond(screenMaximum: maximumFramesPerSecond())
        let movingTimer = Timer(timeInterval: 1.0 / Double(fps), repeats: true) { [weak self] _ in
            self?.coalescer.requestBeat()
        }
        movingTimer.tolerance = 0
        RunLoop.main.add(movingTimer, forMode: .common)
        timer = movingTimer
        activeSource = .repeatingTimer
    }

    private func scheduleOneShot(after interval: TimeInterval) {
        invalidateSources()
        let nextTimer = Timer(timeInterval: interval, repeats: false) { [weak self] _ in
            self?.coalescer.requestBeat()
        }
        RunLoop.main.add(nextTimer, forMode: .common)
        timer = nextTimer
        activeSource = .oneShotTimer
    }

    private func invalidateSources() {
        timer?.invalidate()
        timer = nil
        if #available(macOS 14.0, *), let link = displayLink as? CADisplayLink {
            link.invalidate()
        }
        displayLink = nil
        activeSource = .none
    }

    @available(macOS 14.0, *)
    @objc private func displayLinkDidFire(_ link: CADisplayLink) {
        coalescer.requestBeat()
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
    /// 宠物消失（petVisible==false）：执行层据此清 lastPet/lastWID/bubbleProbe。
    let petDisappeared: Bool
}

/// 跟随 tick 编排纯决策。
enum FollowTickPlanner {
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
}
