import Cocoa

/// 透明（P0 用半透明以便手工观察）NSPanel，作为宠物下方的「底座」。
/// 跨应用窗口相对 z-order 无法用公开 API 精确控制（SC7 降级），
/// 故底座用 .floating level 始终浮于普通窗口之上，并紧贴宠物下方、几何不重叠。
final class DockPanel {
    let dockHeight: CGFloat = 30
    let gap: CGFloat = 2
    let dockWidth: CGFloat = 180
    private let panel: NSPanel
    private var didShow = false

    init() {
        let r = NSRect(x: 0, y: 0, width: dockWidth, height: dockHeight)
        panel = NSPanel(
            contentRect: r,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        // P0：半透明深色底，既能体现「透明面板」又便于肉眼验证跟随；后续可改 alpha=0。
        panel.backgroundColor = NSColor(white: 0.08, alpha: 0.55)
        panel.hasShadow = true
        panel.level = .floating
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isMovableByWindowBackground = false
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        panel.ignoresMouseEvents = false

        let label = NSTextField(labelWithString: "🐾 PetDock")
        label.alignment = .center
        label.textColor = .white
        label.font = .systemFont(ofSize: 12, weight: .medium)
        label.backgroundColor = .clear
        label.frame = panel.contentView?.bounds ?? r
        label.autoresizingMask = [.width, .height]
        panel.contentView?.addSubview(label)
    }

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

    /// 把底座放到宠物窗口（Quartz 全局 rect）正下方，居中、紧贴、不重叠。
    func placeBelow(petQuartzRect pet: CGRect) {
        let dw = max(dockWidth, pet.width)
        let dh = dockHeight
        let dx = pet.origin.x + (pet.width - dw) / 2          // 水平居中于宠物
        let dy = pet.origin.y + pet.height + gap              // Quartz y 增大 = 向下 → 宠物下方
        let dockQuartz = CGRect(x: dx, y: dy, width: dw, height: dh)
        panel.setFrame(Geometry.appKitRectFromQuartz(dockQuartz), display: true)
    }
}
