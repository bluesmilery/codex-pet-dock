import Cocoa
import QuartzCore

/// 底座 frame 的 latest-only 线性插值状态。
/// 只保存当前渲染值与一个在途 segment；没有 Timer、动画队列或预测目标。
struct DockFrameInterpolator {
    static let maximumDuration: TimeInterval = 0.032

    private(set) var renderedFrame: NSRect?
    private(set) var segmentStartFrame: NSRect?
    private(set) var targetFrame: NSRect?
    private(set) var segmentStartedAt: TimeInterval?

    mutating func reset() {
        renderedFrame = nil
        segmentStartFrame = nil
        targetFrame = nil
        segmentStartedAt = nil
    }

    @discardableResult
    mutating func snap(to target: NSRect) -> NSRect {
        renderedFrame = target
        segmentStartFrame = target
        targetFrame = target
        segmentStartedAt = nil
        return target
    }

    /// 取得当前 segment 的值；时间只接受单调时钟，进度始终 clamp 在 [0, 1]。
    mutating func frame(at now: TimeInterval) -> NSRect? {
        guard renderedFrame != nil,
              let start = segmentStartFrame,
              let target = targetFrame,
              let startedAt = segmentStartedAt else {
            return renderedFrame
        }
        let elapsed = now - startedAt
        guard elapsed > 0 else {
            self.renderedFrame = start
            return start
        }
        guard elapsed < Self.maximumDuration else {
            self.renderedFrame = target
            self.segmentStartFrame = target
            self.segmentStartedAt = nil
            return target
        }
        let progress = min(max(elapsed / Self.maximumDuration, 0), 1)
        let sampled = Self.interpolate(start: start, target: target, progress: progress)
        self.renderedFrame = sampled
        return sampled
    }

    /// movementChanged 只允许宠物移动驱动插值；障碍/屏幕等目标变化由调用方 snap。
    @discardableResult
    mutating func update(to target: NSRect, at now: TimeInterval, movementChanged: Bool) -> NSRect {
        guard let currentTarget = targetFrame, renderedFrame != nil else {
            return snap(to: target)
        }
        guard let current = frame(at: now) else {
            return snap(to: target)
        }
        guard currentTarget != target else { return current }
        guard movementChanged else { return snap(to: target) }
        guard current != target else { return snap(to: target) }
        segmentStartFrame = current
        targetFrame = target
        segmentStartedAt = now
        renderedFrame = current
        return current
    }

    private static func interpolate(start: NSRect, target: NSRect, progress: CGFloat) -> NSRect {
        NSRect(
            x: start.origin.x + (target.origin.x - start.origin.x) * progress,
            y: start.origin.y + (target.origin.y - start.origin.y) * progress,
            width: start.width + (target.width - start.width) * progress,
            height: start.height + (target.height - start.height) * progress
        )
    }
}

/// 透明底座 NSPanel：承载 DockView（WEEK LEFT / WEEK TOKENS），紧贴宠物下方、不重叠。
/// 跨应用窗口相对 z-order 无法用公开 API 精确控制（P0 SC7 降级），
/// 故底座用 .floating level 浮于普通窗口之上，并以几何关系紧贴宠物下方。
final class DockPanel {
    let dockHeight: CGFloat = 48
    let gap: CGFloat = 2
    let dockWidth: CGFloat = 200
    private let panel: NSPanel
    private let dockView = DockView()
    private var didShow = false
    private var screenObserver: NSObjectProtocol?
    private var frameInterpolator = DockFrameInterpolator()
    private var lastAvoiding: [CGRect]?
    private var lastVisibleScreenID: ObjectIdentifier?

    var onScreenChange: (() -> Void)?

    /// 点击底座回调（转发给 DockView，用于切换详情卡）。
    var onTap: (() -> Void)? {
        get { dockView.onTap }
        set { dockView.onTap = newValue }
    }

    init() {
        let r = NSRect(x: 0, y: 0, width: dockWidth, height: dockHeight)
        panel = NSPanel(
            contentRect: r,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
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
            self?.lastAvoiding = nil
            self?.lastVisibleScreenID = nil
            self?.onScreenChange?()
        }
    }

    deinit {
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
        lastAvoiding = nil
        lastVisibleScreenID = nil
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
        monotonicNow: TimeInterval = ProcessInfo.processInfo.systemUptime
    ) -> Bool {
        let screenID = visibleScreen.map(ObjectIdentifier.init)
        let screenChanged = lastVisibleScreenID != screenID
        let obstaclesChanged = lastAvoiding != nil && lastAvoiding! != obstacles
        let hasVisibleScreen = visibleScreen != nil
        if !hasVisibleScreen || screenChanged || obstaclesChanged {
            frameInterpolator.reset()
        }
        lastVisibleScreenID = screenID
        lastAvoiding = obstacles

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

        let shouldAnimate = movementChanged && hasVisibleScreen && !screenChanged && !obstaclesChanged
        let frame = frameInterpolator.update(to: target, at: monotonicNow, movementChanged: shouldAnimate)
        panel.setFrame(frame, display: true)
        return true
    }
}
