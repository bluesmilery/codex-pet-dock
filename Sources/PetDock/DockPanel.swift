import Cocoa
import QuartzCore

/// 底座 frame 的 latest-only 插值状态。
/// 只保存当前渲染值与一个在途 segment；没有 Timer、动画队列或预测目标。
/// segment 分两类：movement（宠物窗口实质移动的拖动跟随，32ms 线性）与 avoidance（静止时
/// 内容/障碍/锚目标变化，200ms ease-in-out）；均从当前渲染帧 latest-only 重定向，不排队历史目标。
struct DockFrameInterpolator {
    static let maximumDuration: TimeInterval = 0.032
    static let avoidanceDuration: TimeInterval = 0.2

    enum SegmentKind { case movement, avoidance }

    private(set) var renderedFrame: NSRect?
    private(set) var segmentStartFrame: NSRect?
    private(set) var targetFrame: NSRect?
    private(set) var segmentStartedAt: TimeInterval?
    private(set) var segmentKind: SegmentKind?

    /// 在途 avoidance 段（DockPanel 自有动画渲染源的存活性依据）。
    var isAvoidanceSegmentActive: Bool {
        segmentKind == .avoidance && segmentStartedAt != nil
    }

    mutating func reset() {
        renderedFrame = nil
        segmentStartFrame = nil
        targetFrame = nil
        segmentStartedAt = nil
        segmentKind = nil
    }

    @discardableResult
    mutating func snap(to target: NSRect) -> NSRect {
        renderedFrame = target
        segmentStartFrame = target
        targetFrame = target
        segmentStartedAt = nil
        segmentKind = nil
        return target
    }

    /// 取得当前 segment 的值；时间只接受单调时钟，进度始终 clamp 在 [0, 1]。
    /// movement 段线性；avoidance 段 smoothstep ease-in-out；达到时长后精确落目标并清段。
    mutating func frame(at now: TimeInterval) -> NSRect? {
        guard renderedFrame != nil,
              let start = segmentStartFrame,
              let target = targetFrame,
              let startedAt = segmentStartedAt,
              let kind = segmentKind else {
            return renderedFrame
        }
        // 边界用 now 与 startedAt+duration 直接比较（而非 elapsed<duration 的差值比较）：
        // 浮点加法与字面量常量同域，避免 10+0.2 与 10.2 的表示差让精确终点拍不完成段。
        guard now > startedAt else {
            self.renderedFrame = start
            return start
        }
        let duration = kind == .movement ? Self.maximumDuration : Self.avoidanceDuration
        guard now < startedAt + duration else {
            self.renderedFrame = target
            self.segmentStartFrame = target
            self.segmentStartedAt = nil
            self.segmentKind = nil
            return target
        }
        let elapsed = now - startedAt
        let rawProgress = min(max(elapsed / duration, 0), 1)
        let progress = kind == .avoidance ? Self.smoothstep(rawProgress) : rawProgress
        let sampled = Self.interpolate(start: start, target: target, progress: progress)
        self.renderedFrame = sampled
        return sampled
    }

    /// 宠物移动（movementChanged）驱动的 32ms 线性插值；静止时的内容/障碍/锚目标变化
    /// 由调用方走 updateAvoidance 平滑过渡，安全路径（无屏/换屏/隐藏后）经 reset 后在此 snap。
    /// avoidance 动画中 movement 到来时从当前渲染帧切 movement 段（avoidance 段终止）。
    @discardableResult
    mutating func update(to target: NSRect, at now: TimeInterval) -> NSRect {
        guard let currentTarget = targetFrame, renderedFrame != nil else {
            return snap(to: target)
        }
        guard let current = frame(at: now) else {
            return snap(to: target)
        }
        guard currentTarget != target else { return current }
        guard current != target else { return snap(to: target) }
        segmentStartFrame = current
        targetFrame = target
        segmentStartedAt = now
        segmentKind = .movement
        renderedFrame = current
        return current
    }

    /// 静止时目标变化（内容/障碍/锚，如气泡展开/收起、按钮出现/消失、锚 ±1px 微变）的
    /// avoidance 过渡：从当前渲染帧起 200ms ease-in-out 段。latest-only retarget：动画中
    /// 目标再变从当前渲染帧重启新段（平滑续接，不 snap 截断）；同一目标重放（stable tick）
    /// 继续当前在途段（movement 拖尾或 avoidance 均不重置进度），无在途段且已到位则 snap。
    @discardableResult
    mutating func updateAvoidance(to target: NSRect, at now: TimeInterval) -> NSRect {
        guard renderedFrame != nil, targetFrame != nil else {
            return snap(to: target)
        }
        guard let current = frame(at: now) else {
            return snap(to: target)
        }
        if targetFrame == target, segmentStartedAt != nil {
            return current
        }
        guard current != target else { return snap(to: target) }
        segmentStartFrame = current
        targetFrame = target
        segmentStartedAt = now
        segmentKind = .avoidance
        renderedFrame = current
        return current
    }

    /// smoothstep ease-in-out（3p²−2p³），纯函数可测；t 已 clamp 在 [0, 1]。
    static func smoothstep(_ t: Double) -> Double {
        t * t * (3 - 2 * t)
    }

    private static func interpolate(start: NSRect, target: NSRect, progress: Double) -> NSRect {
        let p = CGFloat(progress)
        return NSRect(
            x: start.origin.x + (target.origin.x - start.origin.x) * p,
            y: start.origin.y + (target.origin.y - start.origin.y) * p,
            width: start.width + (target.width - start.width) * p,
            height: start.height + (target.height - start.height) * p
        )
    }
}

/// 透明底座 NSPanel：承载 DockView（WEEK LEFT / WEEK TOKENS），紧贴宠物下方、不重叠。
/// 跨应用窗口相对 z-order 无法用公开 API 精确控制（P0 SC7 降级），
/// 故底座用 .floating level 浮于普通窗口之上，并以几何关系紧贴宠物下方。
final class DockPanel: NSObject {
    typealias AnimationDisplayLinkFactory = (NSObject, Selector) -> FollowDisplayLink?
    typealias AnimationTimerFactory = (TimeInterval, Bool, @escaping () -> Void) -> FollowTickTimer

    /// macOS 13 / display link 不可用时的 avoidance 动画渲染 fallback 周期（~60Hz）。
    static let avoidanceFallbackInterval: TimeInterval = 1.0 / 60.0

    let dockHeight: CGFloat = 48
    let gap: CGFloat = 2
    let dockWidth: CGFloat = 200
    private let panel: NSPanel
    private let dockView = DockView()
    private var didShow = false
    private var screenObserver: NSObjectProtocol?
    private var frameInterpolator = DockFrameInterpolator()
    private var lastVisibleScreenID: ObjectIdentifier?
    private let makeAnimationDisplayLink: AnimationDisplayLinkFactory
    private let makeAnimationTimer: AnimationTimerFactory
    private let animationMonotonicNow: () -> TimeInterval
    private var animationLink: FollowDisplayLink?
    private var animationTimer: FollowTickTimer?

    var onScreenChange: (() -> Void)?

    /// 点击底座回调（转发给 DockView，用于切换详情卡）。
    var onTap: (() -> Void)? {
        get { dockView.onTap }
        set { dockView.onTap = newValue }
    }

    /// avoidance 动画渲染源注入点（默认真实实现；测试注入 fake 手动 fire）：
    /// - makeAnimationDisplayLink：返回 nil 表示无 display link（macOS 13）→ Timer fallback；
    /// - makeAnimationTimer：fallback repeating Timer 工厂；
    /// - animationMonotonicNow：渲染 tick 的单调时钟。生产默认 systemUptime，与 placeBelow
    ///   生产注入的 followMonotonicNow 同一时钟域；placeBelow 的时间参数是值传入，渲染
    ///   tick 需要独立的“当前时间”来源，故存 provider（测试可控）而非最近一次值。
    init(
        makeAnimationDisplayLink: AnimationDisplayLinkFactory? = nil,
        makeAnimationTimer: @escaping AnimationTimerFactory = DockPanel.makeAnimationRunLoopTimer,
        animationMonotonicNow: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }
    ) {
        let r = NSRect(x: 0, y: 0, width: dockWidth, height: dockHeight)
        let p = NSPanel(
            contentRect: r,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel = p
        if let makeAnimationDisplayLink {
            self.makeAnimationDisplayLink = makeAnimationDisplayLink
        } else {
            // 生产默认：panel 自身 window-bound display link（macOS 14+；13 → Timer fallback）。
            self.makeAnimationDisplayLink = { target, selector in
                guard #available(macOS 14.0, *) else { return nil }
                return p.displayLink(target: target, selector: selector)
            }
        }
        self.makeAnimationTimer = makeAnimationTimer
        self.animationMonotonicNow = animationMonotonicNow
        super.init()
        panel.isOpaque = false
        panel.backgroundColor = .clear       // 透明：圆角由 DockView 的 layer 绘制
        panel.hasShadow = true
        panel.level = .floating
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isMovableByWindowBackground = false
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        panel.ignoresMouseEvents = false
        panel.contentView = dockView
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didChangeScreenNotification,
            object: panel,
            queue: .main
        ) { [weak self] _ in
            self?.frameInterpolator.reset()
            self?.lastVisibleScreenID = nil
            self?.stopAvoidanceAnimation()
            self?.onScreenChange?()
        }
    }

    deinit {
        stopAvoidanceAnimation()
        if let screenObserver { NotificationCenter.default.removeObserver(screenObserver) }
    }

    /// 用展示快照刷新底座 WEEK LEFT / WEEK TOKENS。
    func render(_ s: DockSnapshot) { dockView.render(s) }

    /// 应用主题指标（转发给 DockView），即时换皮。
    func applyTheme(_ m: ThemeMetrics) { dockView.applyTheme(m) }

    var frame: NSRect { panel.frame }
    var isVisible: Bool { panel.isVisible }
    var isDisplayLinkEligible: Bool { panel.isVisible && panel.screen != nil }
    var maximumFramesPerSecond: Int {
        panel.screen?.maximumFramesPerSecond ?? NSScreen.main?.maximumFramesPerSecond ?? 60
    }

    @available(macOS 14.0, *)
    func makeDisplayLink(target: Any, selector: Selector) -> CADisplayLink {
        panel.displayLink(target: target, selector: selector)
    }

    func showIfNeeded() {
        guard !didShow else { return }
        panel.orderFrontRegardless()
        didShow = true
    }

    func hideIfNeeded() {
        frameInterpolator.reset()
        lastVisibleScreenID = nil
        stopAvoidanceAnimation()
        guard didShow else { return }
        panel.orderOut(nil)
        didShow = false
    }

    /// 把底座放到宠物窗口（Quartz 全局 rect）正下方，按 pet 中心水平居中、紧贴、不重叠，并避开 `avoiding`
    /// 障碍；若避让后越出 `visibleScreen` 可见区，则隐藏底座并返回 false。
    /// 底座宽度始终为 `dockWidth`（200）：**不被 pet/障碍宽度撑大**。默认无障碍/无 screen = 原 behavior。
    /// 返回是否显示（false = 已隐藏，但宠物并未消失、不触发数据 pause）。
    @discardableResult
    func placeBelow(
        petQuartzRect pet: CGRect,
        avoiding obstacles: [CGRect] = [],
        visibleScreen: NSScreen? = nil,
        movementChanged: Bool = false,
        monotonicNow: TimeInterval = ProcessInfo.processInfo.systemUptime,
        evidence: (any RuntimeEvidenceRecording)? = nil
    ) -> Bool {
        let screenID = visibleScreen.map(ObjectIdentifier.init)
        let screenChanged = lastVisibleScreenID != screenID
        let hasVisibleScreen = visibleScreen != nil
        // 无屏 / 换屏 → reset（安全路径不得被动画延迟；首次显示 / 隐藏后 renderedFrame
        // 亦为 nil，越界隐藏在下方 hideIfNeeded 内 reset）。
        if !hasVisibleScreen || screenChanged {
            frameInterpolator.reset()
        }
        lastVisibleScreenID = screenID

        let target: NSRect
        if obstacles.isEmpty && visibleScreen == nil {
            let dw = dockWidth, dh = dockHeight
            let dx = pet.origin.x + (pet.width - dw) / 2          // 按 pet 中心对齐（dw 固定 200）
            let dy = pet.origin.y + pet.height + gap
            target = Geometry.appKitRectFromQuartz(CGRect(x: dx, y: dy, width: dw, height: dh))
        } else {
            let r = Geometry.safeDockFrame(pet: pet, avoiding: obstacles,
                                           dockSize: CGSize(width: dockWidth, height: dockHeight), gap: gap, screen: visibleScreen)
            guard let q = r.frame else { hideIfNeeded(); return false }
            target = Geometry.appKitRectFromQuartz(q)
        }

        // 分类（movementChanged 驱动）：movementChanged（宠物窗口是否实质移动，来自
        // Follower.shouldSetFrame）是区分“移动”与“内容/障碍/锚变化”的权威信号——
        // 不再用障碍 count/range 分类（CS 锚变化时障碍 rect 与 adjustedPet.maxY 协变，
        // count 与相对范围均不变，会误入移动路径被 snap；动画中 ±1px 锚微变同理截断在途段）。
        // 1. movementChanged=true → 32ms 线性 movement 段（终止在途 avoidance 段与动画源），
        //    覆盖拖动（含拖动中障碍平移、拖动中按钮出现，32ms 快速跟随优于 snap）；
        // 2. movementChanged=false 且目标变化 → updateAvoidance 200ms smoothstep：无在途段
        //    起段+起动画源，有在途段 latest-only retarget 平滑续接（CS 锚变化自然落入）；
        // 3. movementChanged=false 且目标不变 → hold（在途段继续，由动画源/跟随节拍渲染）。
        // 安全路径（无屏/换屏/首显/隐藏/越界）经上方 reset 后两个入口均立即 snap 并失效动画源。
        let frame: NSRect
        if movementChanged && hasVisibleScreen && !screenChanged {
            frame = frameInterpolator.update(to: target, at: monotonicNow)
        } else {
            frame = frameInterpolator.updateAvoidance(to: target, at: monotonicNow)
        }
        panel.setFrame(frame, display: true)
        // Owner read-back：setFrame 会做像素对齐等状态修正，请求值不等于最终 owner 状态；
        // dy telemetry 只消费写回后的真实 panel.frame（插值状态继续使用请求值，布局行为不变）。
        let ownerFrame = panel.frame
        if let evidence, let bucket = dyBucket(
            actualAppKitFrame: ownerFrame,
            pet: pet,
            screen: visibleScreen
        ) {
            evidence.recordDockDyBucket(bucket)
        }
        // avoidance 动画渲染源生命周期：stable follow tick 静止第 1 秒 0.1s、之后 0.2s
        // 封底，仅靠 tick 采样每段只有约 1-2 个采样点（台阶感）；在途 avoidance 段期间
        // 由 DockPanel 自有 display link（macOS 13 / link 不可用时 60Hz Timer fallback）渲染。
        // movement/snap/隐藏/换屏路径不保留该源：movement 段由 follow scheduler 的 moving
        // 渲染节拍接管，先 terminate 避免与 placeBelow 的每拍 setFrame 双写打架。
        if frameInterpolator.isAvoidanceSegmentActive {
            startAvoidanceAnimationIfNeeded()
        } else {
            stopAvoidanceAnimation()
        }
        return true
    }

    // MARK: - avoidance 动画渲染源（DockPanel 自有，与 FollowTickScheduler 的 moving 源独立共存）

    /// 默认 fallback Timer：与 FollowTickScheduler 的回退同模式（.common mode、tolerance 0），
    /// 但为独立实例——只驱动 avoidance 动画渲染，不与 follow tick 调度共享源。
    private static func makeAnimationRunLoopTimer(
        interval: TimeInterval,
        repeats: Bool,
        callback: @escaping () -> Void
    ) -> FollowTickTimer {
        let timer = Timer(timeInterval: interval, repeats: repeats) { _ in callback() }
        timer.tolerance = 0
        RunLoop.main.add(timer, forMode: .common)
        return timer
    }

    private func startAvoidanceAnimationIfNeeded() {
        guard animationLink == nil, animationTimer == nil else { return }
        if #available(macOS 14.0, *),
           let link = makeAnimationDisplayLink(self, #selector(animationDisplayLinkDidFire(_:))) {
            link.add(to: .main, forMode: .common)
            animationLink = link
            return
        }
        animationTimer = makeAnimationTimer(Self.avoidanceFallbackInterval, true) { [weak self] in
            self?.renderAvoidanceAnimationFrame()
        }
    }

    private func stopAvoidanceAnimation() {
        animationLink?.invalidate()
        animationLink = nil
        animationTimer?.invalidate()
        animationTimer = nil
    }

    @available(macOS 14.0, *)
    @objc private func animationDisplayLinkDidFire(_ link: CADisplayLink) {
        renderAvoidanceAnimationFrame()
    }

    /// 显示节拍渲染在途 avoidance 段；段完成（frame(at:) 精确落目标）后 invalidate 源。
    private func renderAvoidanceAnimationFrame() {
        precondition(Thread.isMainThread)
        guard frameInterpolator.isAvoidanceSegmentActive else {
            stopAvoidanceAnimation()
            return
        }
        let now = animationMonotonicNow()
        guard let rendered = frameInterpolator.frame(at: now) else {
            stopAvoidanceAnimation()
            return
        }
        panel.setFrame(rendered, display: true)
        if !frameInterpolator.isAvoidanceSegmentActive {
            stopAvoidanceAnimation()
        }
    }

    /// 匿名诊断：实际写入 frame 相对本 tick 无障碍基础 frame 的垂直差 bucket。
    /// 只输出 bucket，不输出坐标；基础 frame 按同一几何入口（无障碍）独立重算。
    private func dyBucket(actualAppKitFrame actual: NSRect, pet: CGRect, screen: NSScreen?) -> DockDyBucket? {
        let baseQuartz: CGRect?
        if let screen {
            baseQuartz = Geometry.safeDockFrame(
                pet: pet,
                avoiding: [],
                dockSize: CGSize(width: dockWidth, height: dockHeight),
                gap: gap,
                screen: screen
            ).frame
        } else {
            let dw = dockWidth, dh = dockHeight
            baseQuartz = CGRect(
                x: pet.origin.x + (pet.width - dw) / 2,
                y: pet.origin.y + pet.height + gap,
                width: dw,
                height: dh
            )
        }
        guard let baseQuartz else { return nil }
        let base = Geometry.appKitRectFromQuartz(baseQuartz)
        return DockDyBucket.bucket(dy: abs(actual.midY - base.midY))
    }
}
