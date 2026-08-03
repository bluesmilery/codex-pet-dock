import Cocoa

/// 底座视图：圆角半透明，左侧 WEEK LEFT、右侧 WEEK TOKENS，点击触发详情展开。
/// 纯原生 AppKit（NSStackView + NSTextField）。
final class DockView: NSView {

    /// 点击底座回调（用于切换详情卡）。
    var onTap: (() -> Void)?

    private let leftCaption: NSTextField
    private let leftValue: NSTextField
    private let tokensCaption: NSTextField
    private let tokensValue: NSTextField

    init() {
        leftCaption = DockView.captionLabel("WEEK LEFT")
        leftValue = DockView.valueLabel()
        tokensCaption = DockView.captionLabel("WEEK TOKENS")
        tokensValue = DockView.valueLabel()
        super.init(frame: NSRect(x: 0, y: 0, width: 200, height: 48))
        wantsLayer = true
        layer?.cornerRadius = 10
        layer?.backgroundColor = NSColor(white: 0.08, alpha: 0.65).cgColor

        let leftCol = NSStackView(views: [leftCaption, leftValue])
        leftCol.orientation = .vertical
        leftCol.alignment = .leading

        let rightCol = NSStackView(views: [tokensCaption, tokensValue])
        rightCol.orientation = .vertical
        rightCol.alignment = .leading

        let row = NSStackView(views: [leftCol, rightCol])
        row.orientation = .horizontal
        row.distribution = .fillEqually
        row.edgeInsets = NSEdgeInsets(top: 6, left: 10, bottom: 6, right: 10)
        row.translatesAutoresizingMaskIntoConstraints = false
        addSubview(row)
        NSLayoutConstraint.activate([
            row.leadingAnchor.constraint(equalTo: leadingAnchor),
            row.trailingAnchor.constraint(equalTo: trailingAnchor),
            row.topAnchor.constraint(equalTo: topAnchor),
            row.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) 未实现") }

    /// 用展示快照刷新两行数值。
    func render(_ s: DockSnapshot) {
        leftValue.stringValue = s.rendered(s.weekLeft)
        tokensValue.stringValue = s.rendered(s.weekTokens)
    }

    /// 应用主题指标（背景/圆角/边框/文字色/字体），即时换皮不改变几何。
    func applyTheme(_ m: ThemeMetrics) {
        layer?.backgroundColor = m.background.nsColor.cgColor
        layer?.cornerRadius = m.cornerRadius
        layer?.borderWidth = m.borderWidth
        layer?.borderColor = m.accent.nsColor.cgColor
        let label = m.label.nsColor
        let dim = label.withAlphaComponent(0.6)
        leftCaption.textColor = dim
        tokensCaption.textColor = dim
        leftValue.textColor = label
        tokensValue.textColor = label
        leftCaption.font = DockView.font(m.font, caption: true)
        tokensCaption.font = DockView.font(m.font, caption: true)
        leftValue.font = DockView.font(m.font, caption: false)
        tokensValue.font = DockView.font(m.font, caption: false)
    }

    override func mouseDown(with event: NSEvent) {
        onTap?()
    }

    // MARK: - 工厂

    /// 主题字体 token → 系统字体（system/rounded/monospace），caption 与 value 区分字号/字重。
    private static func font(_ token: ThemeFont, caption: Bool) -> NSFont {
        let size: CGFloat = caption ? 9 : 15
        let weight: NSFont.Weight = caption ? .medium : .semibold
        switch token {
        case .system:     return .systemFont(ofSize: size, weight: weight)
        case .monospace:  return .monospacedSystemFont(ofSize: size, weight: weight)
        case .rounded:
            let desc = NSFont.systemFont(ofSize: size, weight: weight)
                .fontDescriptor.withDesign(.rounded)
            return desc.flatMap { NSFont(descriptor: $0, size: size) }
                ?? .systemFont(ofSize: size, weight: weight)
        }
    }

    private static func captionLabel(_ text: String) -> NSTextField {
        let l = NSTextField(labelWithString: text)
        l.font = .systemFont(ofSize: 9, weight: .medium)
        l.textColor = NSColor.white.withAlphaComponent(0.6)
        l.backgroundColor = .clear
        return l
    }

    private static func valueLabel() -> NSTextField {
        let l = NSTextField(labelWithString: DockSnapshot.placeholder)
        l.font = .systemFont(ofSize: 15, weight: .semibold)
        l.textColor = .white
        l.backgroundColor = .clear
        return l
    }
}
