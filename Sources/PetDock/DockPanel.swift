import Cocoa
import QuartzCore

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
        guard didShow else { return }
        panel.orderOut(nil)
        didShow = false
    }

    /// 把底座放到宠物窗口（Quartz 全局 rect）正下方，按 pet 中心水平居中、紧贴、不重叠，并避开 `avoiding`
    /// 障碍；若避让后越出 `visibleScreen` 可见区，则隐藏底座并返回 false。
    /// 底座宽度始终为 `dockWidth`（200）：**不被 pet/障碍宽度撑大**。默认无障碍/无 screen = 原 behavior。
    /// 返回是否显示（false = 已隐藏，但宠物并未消失、不触发数据 pause）。
    @discardableResult
    func placeBelow(petQuartzRect pet: CGRect, avoiding obstacles: [CGRect] = [], visibleScreen: NSScreen? = nil) -> Bool {
        if obstacles.isEmpty && visibleScreen == nil {
            let dw = dockWidth, dh = dockHeight
            let dx = pet.origin.x + (pet.width - dw) / 2          // 按 pet 中心对齐（dw 固定 200）
            let dy = pet.origin.y + pet.height + gap
            panel.setFrame(Geometry.appKitRectFromQuartz(CGRect(x: dx, y: dy, width: dw, height: dh)), display: true)
            return true
        }
        let r = Geometry.safeDockFrame(pet: pet, avoiding: obstacles,
                                       dockSize: CGSize(width: dockWidth, height: dockHeight), gap: gap, screen: visibleScreen)
        guard let q = r.frame else { hideIfNeeded(); return false }
        panel.setFrame(Geometry.appKitRectFromQuartz(q), display: true)
        return true
    }
}
