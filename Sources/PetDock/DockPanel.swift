import Cocoa

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
    }

    /// 用展示快照刷新底座 WEEK LEFT / WEEK TOKENS。
    func render(_ s: DockSnapshot) { dockView.render(s) }

    /// 应用主题指标（转发给 DockView），即时换皮。
    func applyTheme(_ m: ThemeMetrics) { dockView.applyTheme(m) }

    var frame: NSRect { panel.frame }
    var isVisible: Bool { panel.isVisible }

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

    /// 把底座放到宠物窗口（Quartz 全局 rect）正下方，按 pet 中心水平居中、紧贴、不重叠。
    /// 底座宽度始终为 `dockWidth`（200）：**不被 pet.width 撑大**（实测 Mascot 消失误选 384x95 辅助窗时，
    /// 旧 `max(dockWidth, pet.width)` 会把底座 200→384 突然变宽）。
    func placeBelow(petQuartzRect pet: CGRect) {
        let dw = dockWidth
        let dh = dockHeight
        let dx = pet.origin.x + (pet.width - dw) / 2          // 按 pet 中心对齐（dw 固定 200）
        let dy = pet.origin.y + pet.height + gap              // Quartz y 增大 = 向下 → 宠物下方
        let dockQuartz = CGRect(x: dx, y: dy, width: dw, height: dh)
        panel.setFrame(Geometry.appKitRectFromQuartz(dockQuartz), display: true)
    }
}
