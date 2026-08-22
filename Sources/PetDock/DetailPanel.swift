import Cocoa

/// 详情卡：浮于底座下方，展示 套餐/重置时间/缓存比例/输入/输出/会话数/更新时间/本机估算提示。
/// 点击底座切换展开/关闭；底座隐藏时强制关闭。
final class DetailPanel {

    private let panel: NSPanel
    private var isOpen = false

    private let rowCaptions = ["套餐", "重置时间", "缓存比例", "输入", "输出", "会话数", "更新时间"]
    private let captionLabels: [NSTextField]
    private let rowValues: [NSTextField]
    private let noteLabel: NSTextField
    private let separators: [NSView]
    private let container: NSStackView

    init() {
        captionLabels = rowCaptions.map { DetailPanel.captionLabel($0) }
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
        panel.contentView?.wantsLayer = true
        panel.contentView?.layer?.masksToBounds = true

        container = NSStackView()
        container.orientation = .vertical
        container.alignment = .leading
        container.spacing = 3
        container.edgeInsets = NSEdgeInsets(top: 8, left: 12, bottom: 8, right: 12)
        container.translatesAutoresizingMaskIntoConstraints = false

        var builtSeps: [NSView] = []
        for (i, pair) in zip(captionLabels, rowValues).enumerated() {
            let (capL, val) = pair
            let row = NSStackView(views: [capL, val])
            row.orientation = .horizontal
            row.alignment = .centerY
            row.distribution = .fill
            row.spacing = 8
            row.setContentHuggingPriority(.fittingSizeCompression, for: .horizontal)
            capL.setContentHuggingPriority(.required, for: .horizontal)
            capL.setContentCompressionResistancePriority(.required, for: .horizontal)
            val.setContentHuggingPriority(.defaultLow, for: .horizontal)
            val.setContentCompressionResistancePriority(.required, for: .horizontal)
            container.addArrangedSubview(row)
            if i < captionLabels.count - 1 {
                let sep = DetailPanel.rowSeparator()
                builtSeps.append(sep)
                container.addArrangedSubview(sep)
                sep.heightAnchor.constraint(equalToConstant: 1).isActive = true
            }
        }
        let noteSep = DetailPanel.rowSeparator()
        builtSeps.append(noteSep)
        container.addArrangedSubview(noteSep)
        noteSep.heightAnchor.constraint(equalToConstant: 1).isActive = true
        separators = builtSeps
        container.addArrangedSubview(noteLabel)
        noteLabel.setContentHuggingPriority(.required, for: .vertical)
        noteLabel.setContentHuggingPriority(.fittingSizeCompression, for: .horizontal)
        noteLabel.preferredMaxLayoutWidth = 206

        let contentView = panel.contentView!
        contentView.addSubview(container)
        NSLayoutConstraint.activate([
            container.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            container.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            container.topAnchor.constraint(equalTo: contentView.topAnchor),
            container.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
        ])
        let insetL = container.edgeInsets.left
        let insetR = container.edgeInsets.right
        for view in container.arrangedSubviews {
            view.setContentHuggingPriority(.fittingSizeCompression, for: .horizontal)
            view.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: insetL).isActive = true
            view.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -insetR).isActive = true
        }
        let firstCap = captionLabels[0]
        let firstVal = rowValues[0]
        firstCap.widthAnchor.constraint(greaterThanOrEqualToConstant: 52).isActive = true
        firstVal.widthAnchor.constraint(greaterThanOrEqualToConstant: 72).isActive = true
        for (capL, val) in zip(captionLabels.dropFirst(), rowValues.dropFirst()) {
            capL.widthAnchor.constraint(equalTo: firstCap.widthAnchor).isActive = true
            val.widthAnchor.constraint(equalTo: firstVal.widthAnchor).isActive = true
        }
        fitPanelToContent()
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
        fitPanelToContent()
    }

    /// 应用主题指标（背景/圆角/边框/文字色/字体），即时换皮并按当前字体重算内容高度。
    func applyTheme(_ m: ThemeMetrics) {
        let bg = m.background.nsColor
        let accent = m.accent.nsColor
        let label = m.label.nsColor
        let dim = label.withAlphaComponent(0.6)
        panel.backgroundColor = .clear
        panel.contentView?.wantsLayer = true
        panel.contentView?.layer?.backgroundColor = bg.cgColor
        panel.contentView?.layer?.cornerRadius = m.cornerRadius
        panel.contentView?.layer?.borderWidth = m.borderWidth
        panel.contentView?.layer?.borderColor = accent.cgColor
        for cap in captionLabels {
            cap.textColor = dim
            cap.font = DockView.font(m.font, size: 11, weight: .medium)
        }
        for val in rowValues {
            val.textColor = label
            val.font = DockView.font(m.font, size: 11, weight: .medium)
        }
        noteLabel.textColor = dim
        noteLabel.font = DockView.font(m.font, caption: true)
        let sepColor = label.withAlphaComponent(0.18)
        for sep in separators {
            sep.wantsLayer = true
            sep.layer?.backgroundColor = sepColor.cgColor
        }
        fitPanelToContent()
    }

    /// 切换展开/关闭（相对于底座 frame 定位）。
    func toggle(relativeTo dockFrame: NSRect) {
        isOpen ? close() : open(relativeTo: dockFrame)
    }

    func open(relativeTo dockFrame: NSRect) {
        placeBelow(dockFrame: dockFrame, visibleScreen: screenContaining(dockFrame: dockFrame))
        if !isOpen { panel.orderFrontRegardless(); isOpen = true }
    }

    func close() {
        guard isOpen else { return }
        panel.orderOut(nil)
        isOpen = false
    }

    /// 紧贴底座下方（dockFrame 为 AppKit 全局坐标），相对底座水平居中。
    /// 若传入 `visibleScreen`，对 detail 宽度（≥230）做水平 clamp，避免 dock 贴右边缘时
    /// detail 越出屏幕。
    func placeBelow(dockFrame: NSRect, visibleScreen: NSScreen? = nil) {
        let h = panel.frame.height
        let w = max(dockFrame.width, 230)
        var x = dockFrame.midX - w / 2
        if let v = visibleScreen?.visibleFrame {
            x = min(max(x, v.minX), v.maxX - w)   // 水平 clamp：左不越 visibleMinX，右不越 visibleMaxX-w
        }
        let f = NSRect(x: x, y: dockFrame.origin.y - h - 2, width: w, height: h)
        panel.setFrame(f, display: true)
    }

    /// dockFrame 使用 AppKit 全局坐标；优先中心点，跨屏边界时回退到相交屏幕。
    private func screenContaining(dockFrame: NSRect) -> NSScreen? {
        let center = NSPoint(x: dockFrame.midX, y: dockFrame.midY)
        return NSScreen.screens.first(where: { $0.frame.contains(center) })
            ?? NSScreen.screens.first(where: { $0.frame.intersects(dockFrame) })
    }

    /// 按当前字段、note 与主题字体计算自然高度；面板已打开时固定顶边，保持与 dock 的间距。
    private func fitPanelToContent() {
        let width = max(panel.contentView?.bounds.width ?? 230, 230)
        noteLabel.preferredMaxLayoutWidth = max(0, width - container.edgeInsets.left - container.edgeInsets.right)
        for label in captionLabels + rowValues + [noteLabel] {
            label.invalidateIntrinsicContentSize()
        }
        let arrangedHeight = container.arrangedSubviews.reduce(CGFloat.zero) {
            $0 + $1.fittingSize.height
        }
        let gapsHeight = CGFloat(max(0, container.arrangedSubviews.count - 1)) * container.spacing
        let fittedHeight = container.edgeInsets.top + arrangedHeight + gapsHeight + container.edgeInsets.bottom
        let top = panel.frame.maxY
        panel.setContentSize(NSSize(width: width, height: ceil(fittedHeight)))
        if isOpen {
            var frame = panel.frame
            frame.origin.y = top - frame.height
            panel.setFrame(frame, display: true)
        }
        panel.contentView?.layoutSubtreeIfNeeded()
    }

    // MARK: - 测试钩子

    var frameForTesting: NSRect { panel.frame }
    var collectionBehaviorForTesting: NSWindow.CollectionBehavior { panel.collectionBehavior }

    func layoutForTesting() {
        panel.contentView?.layoutSubtreeIfNeeded()
    }

    var captionsForTesting: [String] { captionLabels.map { $0.stringValue } }
    var valuesForTesting: [String] { rowValues.map { $0.stringValue } }
    var noteForTesting: String { noteLabel.stringValue }
    var captionAlignmentForTesting: NSTextAlignment { captionLabels.first?.alignment ?? .natural }
    var valueAlignmentForTesting: NSTextAlignment { rowValues.first?.alignment ?? .natural }
    var captionWidthsForTesting: [CGFloat] {
        layoutForTesting()
        return captionLabels.map { alignmentRectForTesting($0).width }
    }
    var valueWidthsForTesting: [CGFloat] {
        layoutForTesting()
        return rowValues.map { alignmentRectForTesting($0).width }
    }
    var captionMinXForTesting: [CGFloat] {
        layoutForTesting()
        return captionLabels.map { alignmentRectForTesting($0).minX }
    }
    var valueMaxXForTesting: [CGFloat] {
        layoutForTesting()
        return rowValues.map { alignmentRectForTesting($0).maxX }
    }
    var rowFramesForTesting: [NSRect] {
        layoutForTesting()
        return captionLabels.enumerated().map { i, cap in
            let capF = alignmentRectForTesting(cap)
            let valF = alignmentRectForTesting(rowValues[i])
            return capF.union(valF)
        }
    }
    var noteFrameForTesting: NSRect {
        layoutForTesting()
        return alignmentRectForTesting(noteLabel)
    }
    var separatorCountForTesting: Int { separators.count }
    var separatorFramesForTesting: [NSRect] {
        layoutForTesting()
        guard let cv = panel.contentView else { return [] }
        return separators.map { $0.convert($0.bounds, to: cv) }
    }

    /// Auto Layout 以 alignment rect 为准；NSTextField bounds 会左右各多 2pt cell inset。
    private func alignmentRectForTesting(_ view: NSView) -> NSRect {
        guard let cv = panel.contentView else { return .zero }
        let align = view.alignmentRect(forFrame: view.bounds)
        return view.convert(align, to: cv)
    }
    var contentBoundsForTesting: NSRect { panel.contentView?.bounds ?? .zero }
    var windowBackgroundColorForTesting: NSColor { panel.backgroundColor }
    var contentLayerBackgroundColorForTesting: CGColor? { panel.contentView?.layer?.backgroundColor }
    var borderColorForTesting: CGColor? { panel.contentView?.layer?.borderColor }
    var cornerRadiusForTesting: CGFloat { panel.contentView?.layer?.cornerRadius ?? 0 }
    var borderWidthForTesting: CGFloat { panel.contentView?.layer?.borderWidth ?? 0 }
    var captionColorForTesting: NSColor? { captionLabels.first?.textColor }
    var valueColorForTesting: NSColor? { rowValues.first?.textColor }
    var captionFontForTesting: NSFont? { captionLabels.first?.font }
    var valueFontForTesting: NSFont? { rowValues.first?.font }
    var noteFontForTesting: NSFont? { noteLabel.font }
    var valueFontsForTesting: [NSFont?] { rowValues.map { $0.font } }

    // MARK: - 工厂

    private static func captionLabel(_ text: String) -> NSTextField {
        let l = NSTextField(labelWithString: text)
        l.font = .systemFont(ofSize: 11, weight: .medium)
        l.textColor = NSColor.white.withAlphaComponent(0.55)
        l.backgroundColor = .clear
        l.alignment = .left
        return l
    }

    private static func rowValue() -> NSTextField {
        let l = NSTextField(labelWithString: DockSnapshot.placeholder)
        l.font = .systemFont(ofSize: 11, weight: .medium)
        l.textColor = .white
        l.backgroundColor = .clear
        l.alignment = .right
        return l
    }

    private static func noteLabel() -> NSTextField {
        let l = NSTextField(labelWithString: "")
        l.font = .systemFont(ofSize: 9)
        l.textColor = NSColor.systemYellow.withAlphaComponent(0.9)
        l.backgroundColor = .clear
        l.lineBreakMode = .byWordWrapping
        l.maximumNumberOfLines = 2
        l.preferredMaxLayoutWidth = 200
        l.alignment = .left
        return l
    }

    private static func rowSeparator() -> NSView {
        let v = NSView()
        v.wantsLayer = true
        v.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.12).cgColor
        v.translatesAutoresizingMaskIntoConstraints = false
        return v
    }
}
