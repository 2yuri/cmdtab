import AppKit

/// A borderless, click-through window for drawing over the desktop.
@MainActor
private func makeOverlayWindow(level: NSWindow.Level) -> NSPanel {
    let panel = NSPanel(
        contentRect: .zero,
        styleMask: [.borderless, .nonactivatingPanel],
        backing: .buffered,
        defer: true
    )
    panel.isReleasedWhenClosed = false
    panel.isOpaque = false
    panel.hasShadow = false
    panel.backgroundColor = .clear
    panel.ignoresMouseEvents = true
    panel.level = level
    panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenNone]
    panel.animationBehavior = .none
    return panel
}

/// Dims everything behind the focused window: a dark layer ordered right below it.
@MainActor
final class DimOverlay {
    private let window = makeOverlayWindow(level: .normal)

    init() {
        window.backgroundColor = .black
    }

    /// Covers `screen` and slides just under `windowID`, so only that window stays bright.
    func show(below windowID: CGWindowID, on screen: NSScreen, amount: Double) {
        window.setFrame(screen.frame, display: false)
        window.alphaValue = CGFloat(min(max(amount, 0), 0.9))
        window.order(.below, relativeTo: Int(windowID))
    }

    func hide() {
        window.orderOut(nil)
    }
}

/// The highlighted half of a column a dragged window will stack into.
@MainActor
final class DropZoneOverlay {
    private let window = makeOverlayWindow(level: .floating)
    private let zoneView = DropZoneView()

    init() {
        window.contentView = zoneView
    }

    /// - Parameter rect: in AppKit screen coordinates.
    func show(_ rect: CGRect, label: String) {
        zoneView.label = label
        window.setFrame(rect, display: true)
        window.orderFrontRegardless()
    }

    func hide() {
        window.orderOut(nil)
    }
}

private final class DropZoneView: NSView {
    var label = "" { didSet { needsDisplay = true } }

    override func draw(_ dirtyRect: NSRect) {
        let volt = NSColor(named: "Volt") ?? .systemGreen
        let shape = NSBezierPath(roundedRect: bounds.insetBy(dx: 2, dy: 2), xRadius: 10, yRadius: 10)
        volt.withAlphaComponent(0.2).setFill()
        shape.fill()
        volt.setStroke()
        shape.lineWidth = 3
        shape.stroke()

        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 13, weight: .semibold),
            .foregroundColor: NSColor(named: "Ink") ?? .black,
        ]
        let text = NSAttributedString(string: label, attributes: attributes)
        let textSize = text.size()
        let pill = CGRect(
            x: bounds.midX - textSize.width / 2 - 12,
            y: bounds.maxY - textSize.height - 30,
            width: textSize.width + 24,
            height: textSize.height + 12
        )
        volt.setFill()
        NSBezierPath(roundedRect: pill, xRadius: 7, yRadius: 7).fill()
        text.draw(at: CGPoint(x: pill.minX + 12, y: pill.minY + 6))
    }
}

/// A small bar at the bottom of the screen: one block per column, the focused one in Volt, and a
/// white frame around the part of the strip that's on screen. Appears when focus moves or the strip
/// scrolls, and fades out on its own.
@MainActor
final class StripMapHUD {
    struct Map {
        /// Each column along the strip, as shares of the screen width.
        var columns: [(offset: Double, width: Double)]
        var focused: Int?
        /// The on-screen part, as shares of the screen width (its width is always 1).
        var viewOffset: Double
    }

    private let window = makeOverlayWindow(level: .statusBar)
    private let mapView = StripMapView()
    private var hideTask: Task<Void, Never>?

    init() {
        window.contentView = mapView
    }

    func flash(_ map: Map, on screen: NSScreen) {
        guard map.columns.count > 1 else { return hide() }
        mapView.map = map
        let size = mapView.fittingSize
        let visible = screen.visibleFrame
        window.setFrame(
            CGRect(x: visible.midX - size.width / 2, y: visible.minY + 10, width: size.width, height: size.height),
            display: true
        )
        window.alphaValue = 1
        window.orderFrontRegardless()

        hideTask?.cancel()
        hideTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(1200))
            guard !Task.isCancelled else { return }
            NSAnimationContext.current.duration = 0.3
            self?.window.animator().alphaValue = 0
            try? await Task.sleep(for: .milliseconds(320))
            guard !Task.isCancelled else { return }
            self?.window.orderOut(nil)
        }
    }

    func hide() {
        hideTask?.cancel()
        window.orderOut(nil)
    }
}

private final class StripMapView: NSView {
    var map = StripMapHUD.Map(columns: [], focused: nil, viewOffset: 0) { didSet { needsDisplay = true } }

    /// Points in the map for one screen width.
    private static let unit: CGFloat = 72
    private static let blockHeight: CGFloat = 26
    private static let blockInset: CGFloat = 2
    private static let padding: CGFloat = 10

    /// The map spans the strip and the on-screen frame, whichever reaches further.
    private var extent: (start: Double, end: Double) {
        let stripEnd = map.columns.last.map { $0.offset + $0.width } ?? 0
        return (min(0, map.viewOffset), max(stripEnd, map.viewOffset + 1))
    }

    override var fittingSize: NSSize {
        let span = CGFloat(extent.end - extent.start) * Self.unit
        return NSSize(width: span + Self.padding * 2, height: Self.blockHeight + Self.padding * 2)
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor(calibratedWhite: 0.11, alpha: 0.85).setFill()
        NSBezierPath(roundedRect: bounds, xRadius: 12, yRadius: 12).fill()

        let origin = Self.padding - CGFloat(extent.start) * Self.unit
        let volt = NSColor(named: "Volt") ?? .systemGreen
        for (index, column) in map.columns.enumerated() {
            let rect = CGRect(
                x: origin + CGFloat(column.offset) * Self.unit + Self.blockInset,
                y: Self.padding,
                width: max(CGFloat(column.width) * Self.unit - Self.blockInset * 2, 4),
                height: Self.blockHeight
            )
            (index == map.focused ? volt : NSColor.white.withAlphaComponent(0.3)).setFill()
            NSBezierPath(roundedRect: rect, xRadius: 4, yRadius: 4).fill()
        }

        let view = CGRect(
            x: origin + CGFloat(map.viewOffset) * Self.unit - 1,
            y: Self.padding - 4,
            width: Self.unit + 2,
            height: Self.blockHeight + 8
        )
        let frame = NSBezierPath(roundedRect: view, xRadius: 7, yRadius: 7)
        frame.lineWidth = 2
        NSColor.white.setStroke()
        frame.stroke()
    }
}
