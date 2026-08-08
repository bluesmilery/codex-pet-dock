import Cocoa

/// 详情卡：浮于底座下方，展示 套餐/重置时间/缓存比例/输入/输出/会话数/更新时间/本机估算提示。
/// 点击底座切换展开/关闭；底座隐藏时强制关闭。
final class DetailPanel {

    private let panel: NSPanel
    private var isOpen = false

    private let rowCaptions = ["套餐", "重置时间", "缓存比例", "输入", "输出", "会话数", "更新时间"]
    private let rowValues: [NSTextField]
    private let noteLabel: NSTextField

    init() {
        rowValues = rowCaptions.map { _ in DetailPanel.rowValue() }
        noteLabel = DetailPanel.noteLabel()
        let r = NSRect(x: 0, y: 0, width: 230, height: 190)
        panel = NSPanel(contentRect: r, styleMask: [.borderless, .nonactivatingPanel],
                        backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = NSColor(white: 0.06, alpha: 0.88)
        panel.hasShadow = true
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isMovableByWindowBackground = false

        let container = NSStackView()
        container.orientation = .vertical
        container.alignment = .leading
        container.spacing = 5
        container.edgeInsets = NSEdgeInsets(top: 10, left: 12, bottom: 10, right: 12)
        container.translatesAutoresizingMaskIntoConstraints = false

        for (cap, val) in zip(rowCaptions, rowValues) {
            let capL = NSTextField(labelWithString: cap)
            capL.font = .systemFont(ofSize: 10)
            capL.textColor = NSColor.white.withAlphaComponent(0.55)
            capL.backgroundColor = .clear
            let row = NSStackView(views: [capL, val])
            row.orientation = .horizontal
            row.spacing = 8
            val.setContentCompressionResistancePriority(.defaultHigh, for: .horizontal)
            container.addArrangedSubview(row)
        }
        let sep = NSBox()
        sep.boxType = .separator
        container.addArrangedSubview(sep)
        container.addArrangedSubview(noteLabel)

        let contentView = panel.contentView!
        contentView.addSubview(container)
        NSLayoutConstraint.activate([
            container.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            container.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            container.topAnchor.constraint(equalTo: contentView.topAnchor),
            container.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
        ])
    }

    var isVisible: Bool { isOpen }

    /// 用展示快照刷新详情字段。
    func render(_ s: DockSnapshot) {
        let vals = [s.plan, s.resetAt, s.cacheRatio, s.inputTokens, s.outputTokens,
                    s.sessionString, s.updatedAt]
        for (i, v) in vals.enumerated() where i < rowValues.count {
            rowValues[i].stringValue = s.rendered(v)
        }
        noteLabel.stringValue = s.localEstimateNote
    }

    /// 切换展开/关闭（相对于底座 frame 定位）。
    func toggle(relativeTo dockFrame: NSRect) {
        isOpen ? close() : open(relativeTo: dockFrame)
    }

    func open(relativeTo dockFrame: NSRect) {
        placeBelow(dockFrame: dockFrame)
        if !isOpen { panel.orderFrontRegardless(); isOpen = true }
    }

    func close() {
        guard isOpen else { return }
        panel.orderOut(nil)
        isOpen = false
    }

    /// 紧贴底座下方（dockFrame 为 AppKit 全局坐标），水平与底座对齐。
    /// 若传入 `visibleScreen`，对 detail 宽度（≥230）做水平 clamp，避免 dock 贴右边缘时
    /// detail 右侧越出屏幕（detail 宽 max(dockWidth,230) > dock 宽 200，从同一 x 起算会超 30px）。
    func placeBelow(dockFrame: NSRect, visibleScreen: NSScreen? = nil) {
        let h = panel.frame.height
        let w = max(dockFrame.width, 230)
        var x = dockFrame.origin.x
        if let v = visibleScreen?.visibleFrame {
            x = min(max(x, v.minX), v.maxX - w)   // 水平 clamp：左不越 visibleMinX，右不越 visibleMaxX-w
        }
        let f = NSRect(x: x, y: dockFrame.origin.y - h - 2, width: w, height: h)
        panel.setFrame(f, display: true)
    }

    // MARK: - 测试钩子

    var frameForTesting: NSRect { panel.frame }
    var collectionBehaviorForTesting: NSWindow.CollectionBehavior { panel.collectionBehavior }

    // MARK: - 工厂

    private static func rowValue() -> NSTextField {
        let l = NSTextField(labelWithString: DockSnapshot.placeholder)
        l.font = .systemFont(ofSize: 11, weight: .medium)
        l.textColor = .white
        l.backgroundColor = .clear
        return l
    }

    private static func noteLabel() -> NSTextField {
        let l = NSTextField(labelWithString: "")
        l.font = .systemFont(ofSize: 9)
        l.textColor = NSColor.systemYellow.withAlphaComponent(0.9)
        l.backgroundColor = .clear
        l.lineBreakMode = .byTruncatingTail
        l.maximumNumberOfLines = 2
        l.preferredMaxLayoutWidth = 200
        return l
    }
}
