import AppKit

/// The search bar at the top of the switcher (design: 04 · Switcher Modes → Search): magnifier,
/// a large borderless field, the result count and a hairline underneath. No system search-field bezel.
final class SearchBarView: NSView {
    static let height: CGFloat = 48

    let field = NSTextField()
    private let icon = NSImageView()
    private let countLabel = NSTextField(labelWithString: "")
    private let hairline = NSView()

    override init(frame: NSRect) {
        super.init(frame: frame)

        icon.image = NSImage(systemSymbolName: "magnifyingglass", accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 18, weight: .regular))
        icon.contentTintColor = .secondaryLabelColor
        addSubview(icon)

        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = .systemFont(ofSize: 20)
        field.textColor = .labelColor
        field.cell?.isScrollable = true
        field.cell?.wraps = false
        addSubview(field)

        countLabel.font = .systemFont(ofSize: 12)
        countLabel.textColor = .secondaryLabelColor
        countLabel.alignment = .right
        addSubview(countLabel)

        hairline.wantsLayer = true
        addSubview(hairline)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    func update(placeholder: String, resultCount: Int) {
        field.placeholderAttributedString = NSAttributedString(string: placeholder, attributes: [
            .font: NSFont.systemFont(ofSize: 20),
            .foregroundColor: NSColor.tertiaryLabelColor,
        ])
        countLabel.stringValue = resultCount == 1 ? "1 window" : "\(resultCount) windows"
        needsLayout = true
    }

    override func layout() {
        super.layout()
        let inset: CGFloat = 16
        icon.frame = NSRect(x: inset, y: (bounds.height - 20) / 2, width: 20, height: 20)
        countLabel.sizeToFit()
        countLabel.frame.origin = NSPoint(
            x: bounds.width - inset - countLabel.frame.width,
            y: (bounds.height - countLabel.frame.height) / 2
        )
        let fieldX = icon.frame.maxX + 12
        let fieldHeight: CGFloat = 26
        field.frame = NSRect(
            x: fieldX,
            y: (bounds.height - fieldHeight) / 2,
            width: max(countLabel.frame.minX - 12 - fieldX, 0),
            height: fieldHeight
        )
        hairline.frame = NSRect(x: 0, y: 0, width: bounds.width, height: 1)
    }

    override func updateLayer() {
        super.updateLayer()
        hairline.layer?.backgroundColor = NSColor.labelColor.withAlphaComponent(0.1).cgColor
    }

    override var wantsUpdateLayer: Bool { true }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        hairline.layer?.backgroundColor = NSColor.labelColor.withAlphaComponent(0.1).cgColor
    }
}

/// "↩ Open  ⇥ Next  esc Close" along the bottom of the switcher while searching.
final class KeyHintsView: NSView {
    static let height: CGFloat = 34
    private static let hints = [("↩", "Open"), ("⇥", "Next"), ("esc", "Close")]

    private let hairline = NSView()

    override init(frame: NSRect) {
        super.init(frame: frame)
        hairline.wantsLayer = true
        addSubview(hairline)

        var x: CGFloat = 16
        for (key, label) in Self.hints {
            let cap = NSTextField(labelWithString: key)
            cap.font = .monospacedSystemFont(ofSize: 10, weight: .medium)
            cap.textColor = .labelColor
            cap.alignment = .center
            cap.sizeToFit()
            let capBox = NSView(frame: NSRect(x: x, y: (Self.height - 18) / 2, width: max(cap.frame.width + 12, 22), height: 18))
            capBox.wantsLayer = true
            capBox.layer?.cornerRadius = 5
            capBox.layer?.backgroundColor = NSColor.labelColor.withAlphaComponent(0.12).cgColor
            cap.frame = NSRect(x: 0, y: (18 - cap.frame.height) / 2, width: capBox.frame.width, height: cap.frame.height)
            capBox.addSubview(cap)
            addSubview(capBox)

            let text = NSTextField(labelWithString: label)
            text.font = .systemFont(ofSize: 11)
            text.textColor = .secondaryLabelColor
            text.sizeToFit()
            text.frame.origin = NSPoint(x: capBox.frame.maxX + 6, y: (Self.height - text.frame.height) / 2)
            addSubview(text)
            x = text.frame.maxX + 16
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func layout() {
        super.layout()
        hairline.frame = NSRect(x: 0, y: bounds.height - 1, width: bounds.width, height: 1)
        hairline.layer?.backgroundColor = NSColor.labelColor.withAlphaComponent(0.08).cgColor
    }
}
