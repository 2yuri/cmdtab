import AppKit

/// What every switcher tile shares: selection highlight, hover and click.
class SwitcherTileView: NSView {
    static let inset: CGFloat = 8
    static let cornerRadius: CGFloat = 12
    static let dimmedAlpha: CGFloat = 0.45

    var onHover: (() -> Void)?
    var onClick: (() -> Void)?

    var isSelected = false {
        didSet {
            guard isSelected != oldValue else { return }
            needsDisplay = true
        }
    }

    init(item: SwitcherItem, frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.cornerRadius = Self.cornerRadius
        layer?.cornerCurve = .continuous
        toolTip = item.tooltip
        setAccessibilityRole(.button)
        setAccessibilityLabel(item.windowCount > 1 ? "\(item.primary.appName), \(item.windowCount) windows" : item.tooltip)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    /// Previews override this; icon tiles have nothing to update.
    func setThumbnail(_ image: NSImage) {}

    /// Matches of `highlight` (the search query) in the title are drawn in the accent colour.
    static func titleField(
        _ item: SwitcherItem,
        fontSize: CGFloat,
        lines: Int,
        alignment: NSTextAlignment = .natural,
        highlight: String
    ) -> NSTextField {
        let field = lines > 1 ? NSTextField(wrappingLabelWithString: item.title) : NSTextField(labelWithString: item.title)
        field.font = .systemFont(ofSize: fontSize)
        field.maximumNumberOfLines = lines
        field.lineBreakMode = .byTruncatingTail
        field.cell?.truncatesLastVisibleLine = true
        field.alignment = alignment
        field.textColor = item.isDimmed ? .secondaryLabelColor : .labelColor

        let ranges = SearchFilter.highlightRanges(highlight, in: item.title)
        if !ranges.isEmpty {
            let paragraph = NSMutableParagraphStyle()
            paragraph.alignment = alignment
            paragraph.lineBreakMode = .byTruncatingTail
            let text = NSMutableAttributedString(string: item.title, attributes: [
                .font: NSFont.systemFont(ofSize: fontSize),
                .foregroundColor: field.textColor ?? .labelColor,
                .paragraphStyle: paragraph,
            ])
            for range in ranges {
                text.addAttributes([
                    .foregroundColor: NSColor(named: "AccentColor") ?? .controlAccentColor,
                    .font: NSFont.systemFont(ofSize: fontSize, weight: .semibold),
                ], range: range)
            }
            field.attributedStringValue = text
        }
        return field
    }

    /// Neutral pill with a layers icon and the desktop number, for windows on another desktop.
    static func desktopBadge(_ number: Int) -> NSView {
        let height: CGFloat = 18
        let icon = NSImageView(image: NSImage(systemSymbolName: "square.3.layers.3d", accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 9, weight: .semibold)) ?? NSImage())
        icon.contentTintColor = NSColor.white.withAlphaComponent(0.8)
        icon.frame = NSRect(x: 6, y: (height - 11) / 2, width: 11, height: 11)

        let label = NSTextField(labelWithString: "\(number)")
        label.font = .systemFont(ofSize: 10, weight: .bold)
        label.textColor = NSColor.white.withAlphaComponent(0.9)
        label.sizeToFit()
        label.frame.origin = NSPoint(x: icon.frame.maxX + 3, y: (height - label.frame.height) / 2)

        let badge = NSView(frame: NSRect(x: 0, y: 0, width: label.frame.maxX + 6, height: height))
        badge.wantsLayer = true
        badge.layer?.cornerRadius = 8
        badge.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.45).cgColor
        badge.layer?.borderWidth = 1
        badge.layer?.borderColor = NSColor.white.withAlphaComponent(0.15).cgColor
        badge.addSubview(icon)
        badge.addSubview(label)
        badge.setAccessibilityElement(true)
        badge.setAccessibilityLabel("Desktop \(number)")
        return badge
    }

    /// "2", "3"… on grouped tiles, centred on the top-right corner of `anchor`.
    func addCountBadge(_ count: Int, cornerOf anchor: NSRect) {
        guard count > 1 else { return }
        let label = NSTextField(labelWithString: "\(count)")
        label.font = .systemFont(ofSize: 11, weight: .bold)
        label.alignment = .center
        label.textColor = NSColor(name: nil) { $0.isDark ? NSColor(named: "Ink") ?? .black : .white }
        label.sizeToFit()

        let height: CGFloat = 18
        let width = max(height, label.frame.width + 10)
        let badge = NSView(frame: NSRect(
            x: min(anchor.maxX - width / 2 - 2, bounds.width - width - 2),
            y: min(anchor.maxY - height / 2 - 2, bounds.height - height - 2),
            width: width,
            height: height
        ))
        badge.wantsLayer = true
        badge.layer?.cornerRadius = height / 2
        badge.layer?.backgroundColor = (NSColor(named: "AccentColor") ?? .controlAccentColor).cgColor
        label.frame = NSRect(x: 0, y: (height - label.frame.height) / 2, width: width, height: label.frame.height)
        badge.addSubview(label)
        addSubview(badge)
    }

    override var wantsUpdateLayer: Bool { true }

    override func updateLayer() {
        layer?.backgroundColor = isSelected
            ? NSColor.labelColor.withAlphaComponent(0.16).cgColor
            : NSColor.clear.cgColor
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(
            rect: .zero,
            options: [.mouseMoved, .activeAlways, .inVisibleRect],
            owner: self
        ))
    }

    // Hover follows real mouse movement only. Reacting to "entered" would select whatever tile
    // happens to appear under a still cursor and fight the keyboard.
    override func mouseMoved(with event: NSEvent) {
        guard !isSelected else { return }
        onHover?()
    }

    override func mouseUp(with event: NSEvent) {
        onClick?()
    }

    // The panel never becomes key, so accept the first click directly.
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

/// Large app icon with the window title underneath.
final class IconTileView: SwitcherTileView {
    private static let topInset: CGFloat = 10

    init(item: SwitcherItem, origin: NSPoint, metrics: SwitcherItemMetrics, highlight: String) {
        let size = metrics.itemSize
        super.init(item: item, frame: NSRect(origin: origin, size: size))

        let iconView = NSImageView(frame: NSRect(
            x: (size.width - metrics.iconSide) / 2,
            y: size.height - Self.topInset - metrics.iconSide,
            width: metrics.iconSide,
            height: metrics.iconSide
        ))
        iconView.image = item.primary.icon
        iconView.imageScaling = .scaleProportionallyUpOrDown
        iconView.alphaValue = item.isDimmed ? Self.dimmedAlpha : 1
        addSubview(iconView)
        addCountBadge(item.windowCount, cornerOf: iconView.frame)
        if let desktop = item.primary.desktopNumber {
            let badge = Self.desktopBadge(desktop)
            badge.frame.origin = NSPoint(x: iconView.frame.minX - 6, y: iconView.frame.minY - 2)
            addSubview(badge)
        }

        let title = Self.titleField(item, fontSize: metrics.fontSize, lines: 2, alignment: .center, highlight: highlight)
        title.frame = NSRect(
            x: 6,
            y: iconView.frame.minY - 4 - metrics.titleHeight,
            width: size.width - 12,
            height: metrics.titleHeight
        )
        addSubview(title)
    }
}

/// Window snapshot with a small app icon and one line of title underneath. Until the snapshot
/// arrives it shows the app icon in the middle of the preview area.
final class PreviewTileView: SwitcherTileView {
    private static let placeholderIconSide: CGFloat = 48
    private let previewView = NSImageView()
    private let previewArea: NSRect
    private let isDimmed: Bool

    init(item: SwitcherItem, origin: NSPoint, metrics: SwitcherItemMetrics, thumbnail: NSImage?, highlight: String) {
        let size = metrics.itemSize
        previewArea = NSRect(
            x: (size.width - metrics.previewSize.width) / 2,
            y: size.height - Self.inset - metrics.previewSize.height,
            width: metrics.previewSize.width,
            height: metrics.previewSize.height
        )
        isDimmed = item.isDimmed
        super.init(item: item, frame: NSRect(origin: origin, size: size))

        previewView.imageScaling = .scaleProportionallyUpOrDown
        previewView.wantsLayer = true
        previewView.layer?.cornerRadius = 6
        previewView.layer?.masksToBounds = true
        addSubview(previewView)

        let labelHeight = ceil(metrics.fontSize * 1.4)
        let labelY = (previewArea.minY - labelHeight) / 2
        let badge = NSImageView(frame: NSRect(
            x: Self.inset,
            y: labelY + (labelHeight - metrics.iconSide) / 2,
            width: metrics.iconSide,
            height: metrics.iconSide
        ))
        badge.image = item.primary.icon
        badge.imageScaling = .scaleProportionallyUpOrDown
        addSubview(badge)

        let title = Self.titleField(item, fontSize: metrics.fontSize, lines: 1, highlight: highlight)
        title.frame = NSRect(
            x: badge.frame.maxX + 6,
            y: labelY,
            width: size.width - badge.frame.maxX - 6 - Self.inset,
            height: labelHeight
        )
        addSubview(title)

        if let thumbnail {
            setThumbnail(thumbnail)
        } else {
            showPlaceholder(item.primary.icon)
        }
        addCountBadge(item.windowCount, cornerOf: previewArea.insetBy(dx: 6, dy: 6))
        if let desktop = item.primary.desktopNumber {
            let badge = Self.desktopBadge(desktop)
            badge.frame.origin = NSPoint(x: previewArea.minX + 6, y: previewArea.minY + 6)
            addSubview(badge)
        }
    }

    override func setThumbnail(_ image: NSImage) {
        guard image.size.width > 0, image.size.height > 0 else { return }
        // Fit the snapshot's aspect ratio inside the preview area, centred.
        let scale = min(previewArea.width / image.size.width, previewArea.height / image.size.height)
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        previewView.frame = NSRect(
            x: previewArea.midX - size.width / 2,
            y: previewArea.midY - size.height / 2,
            width: size.width,
            height: size.height
        )
        previewView.image = image
        previewView.alphaValue = isDimmed ? Self.dimmedAlpha : 1
    }

    private func showPlaceholder(_ icon: NSImage?) {
        let side = Self.placeholderIconSide
        previewView.frame = NSRect(x: previewArea.midX - side / 2, y: previewArea.midY - side / 2, width: side, height: side)
        previewView.image = icon
        previewView.alphaValue = Self.dimmedAlpha
    }
}

/// One row of the titles list: small icon, window title, app name in grey, window count.
final class TitleTileView: SwitcherTileView {
    init(item: SwitcherItem, origin: NSPoint, metrics: SwitcherItemMetrics, highlight: String) {
        let size = metrics.itemSize
        super.init(item: item, frame: NSRect(origin: origin, size: size))
        layer?.cornerRadius = 8

        let icon = NSImageView(frame: NSRect(
            x: 10,
            y: (size.height - metrics.iconSide) / 2,
            width: metrics.iconSide,
            height: metrics.iconSide
        ))
        icon.image = item.primary.icon
        icon.imageScaling = .scaleProportionallyUpOrDown
        icon.alphaValue = item.isDimmed ? Self.dimmedAlpha : 1
        addSubview(icon)

        var trailing = size.width - 10
        if item.windowCount > 1 {
            let count = Self.secondaryLabel("\(item.windowCount) windows", fontSize: metrics.fontSize - 1)
            count.sizeToFit()
            trailing -= count.frame.width
            count.frame.origin = NSPoint(x: trailing, y: (size.height - count.frame.height) / 2)
            addSubview(count)
            trailing -= 12
        } else if item.primary.title != item.primary.appName {
            let app = Self.secondaryLabel(item.primary.appName, fontSize: metrics.fontSize - 1)
            app.sizeToFit()
            let width = min(app.frame.width, size.width * 0.3)
            trailing -= width
            app.frame = NSRect(x: trailing, y: (size.height - app.frame.height) / 2, width: width, height: app.frame.height)
            addSubview(app)
            trailing -= 12
        }

        if let desktop = item.primary.desktopNumber {
            let badge = Self.desktopBadge(desktop)
            trailing -= badge.frame.width
            badge.frame.origin = NSPoint(x: trailing, y: (size.height - badge.frame.height) / 2)
            addSubview(badge)
            trailing -= 10
        }

        let title = Self.titleField(item, fontSize: metrics.fontSize, lines: 1, highlight: highlight)
        title.sizeToFit()
        let titleX = icon.frame.maxX + 10
        title.frame = NSRect(
            x: titleX,
            y: (size.height - title.frame.height) / 2,
            width: max(trailing - titleX, 0),
            height: title.frame.height
        )
        addSubview(title)
    }

    private static func secondaryLabel(_ text: String, fontSize: CGFloat) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: fontSize)
        label.textColor = .secondaryLabelColor
        label.lineBreakMode = .byTruncatingTail
        return label
    }
}
