import AppKit
import Carbon.HIToolbox

/// Arrange mode's bar at the bottom of the screen: one numbered tile per column (app icon and
/// number, the focused one in Volt), key hints, and tiles that can be dragged to reorder columns.
@MainActor
final class ArrangeHUD {
    struct Tile {
        /// One window of the column, top to bottom (a stack has two or three).
        struct Part {
            var icon: NSImage?
            /// A snapshot, when previews are on and Screen Recording is allowed.
            var preview: NSImage?
            /// Share of the column's height.
            var height: Double
        }

        var parts: [Part]
        var width: Double // Share of the screen, so tiles keep the columns' proportions.

        var icon: NSImage? { parts.first?.icon }
    }

    /// A tile was dragged from one place to another.
    var onReorder: ((_ from: Int, _ to: Int) -> Void)?
    /// A tile was clicked.
    var onSelect: ((Int) -> Void)?
    /// A tile was dropped onto another: stack the first column into the second, like S.
    var onStack: ((_ from: Int, _ into: Int) -> Void)?
    /// A key was pressed while the bar has the keyboard.
    var onKey: ((HotKeyCenter.Action) -> Void)?
    /// The bar lost the keyboard (the user clicked another window).
    var onResignKey: (() -> Void)?

    private let panel: NSPanel
    private let view = ArrangeHUDView()

    init() {
        // The bar takes the keyboard (without activating CmdTab), so plain keys like S and 1–9 reach it
        // even when Secure Input hides them from hot keys and event taps.
        panel = KeyTakingPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        panel.isReleasedWhenClosed = false
        panel.isOpaque = false
        panel.hasShadow = true
        panel.backgroundColor = .clear
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenNone]
        panel.becomesKeyOnlyIfNeeded = true
        panel.contentView = view
        view.onReorder = { [weak self] from, to in self?.onReorder?(from, to) }
        view.onSelect = { [weak self] index in self?.onSelect?(index) }
        view.onStack = { [weak self] from, into in self?.onStack?(from, into) }
        view.onKey = { [weak self] action in self?.onKey?(action) }
        NotificationCenter.default.addObserver(
            forName: NSWindow.didResignKeyNotification, object: panel, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.panel.isVisible else { return }
                self.onResignKey?()
            }
        }
    }

    var isVisible: Bool { panel.isVisible }

    func show(
        _ tiles: [Tile], focused: Int?, stackPrompt: Bool = false, showsHeight: Bool = false,
        note: String? = nil, on screen: NSScreen
    ) {
        view.tiles = tiles
        view.focused = focused
        view.stackPrompt = stackPrompt
        view.showsHeight = showsHeight
        view.note = note
        let visible = screen.visibleFrame
        view.maxWidth = visible.width - 96
        let size = view.fittingSize
        panel.setFrame(
            CGRect(x: visible.midX - size.width / 2, y: visible.minY + 24, width: size.width, height: size.height),
            display: true
        )
        panel.orderFrontRegardless()
        if !panel.isKeyWindow {
            panel.makeKey()
            panel.makeFirstResponder(view)
        }
    }

    func hide() {
        panel.orderOut(nil)
    }

    /// Which tiles fit in `available` points when there are too many: a run around the focused one with
    /// three neighbours on each side when they exist, sliding one tile at a time as focus moves (like a
    /// scroll), with room kept for a "…" marker on each side that hides tiles.
    nonisolated static func visibleRange(
        widths: [CGFloat], focused: Int?, previousStart: Int, available: CGFloat, gap: CGFloat, marker: CGFloat
    ) -> Range<Int> {
        let count = widths.count
        guard count > 0 else { return 0..<0 }
        let total = widths.reduce(0, +) + gap * CGFloat(count - 1)
        guard total > available else { return 0..<count }

        // Room for both markers is always kept once tiles overflow, so the run slides one tile at a time.
        let room = available - 2 * (marker + gap)
        func end(from start: Int) -> Int {
            var used: CGFloat = 0
            var index = start
            while index < count {
                let width = widths[index] + (index > start ? gap : 0)
                if used + width > room && index > start { break }
                used += width
                index += 1
            }
            return index
        }

        // Keep `context` tiles on each side of the focused one in view whenever they exist, so you
        // always see what's next to it; slide only as far as that needs.
        let context = 3
        var start = min(max(previousStart, 0), count - 1)
        let focused = min(max(focused ?? start, 0), count - 1)
        start = min(start, max(focused - context, 0))
        let lastNeeded = min(focused + context, count - 1)
        while lastNeeded >= end(from: start) && start < focused { start += 1 }
        return start..<end(from: start)
    }

    /// The Arrange mode action for a key, or `nil` to ignore it. One key per command.
    /// - Parameter stacking: Stack mode (after S): ← → stack with that side, D unstacks, S or esc go back.
    nonisolated static func action(keyCode: Int, flags: NSEvent.ModifierFlags, stacking: Bool = false) -> HotKeyCenter.Action? {
        if flags.contains(.control) { return nil }
        let shift = flags.contains(.shift), option = flags.contains(.option), command = flags.contains(.command)
        let plain = !shift && !option && !command

        if stacking {
            guard plain else { return nil }
            switch keyCode {
            case kVK_LeftArrow: return .arrangeStackLeft
            case kVK_RightArrow: return .arrangeStackRight
            case kVK_ANSI_D: return .arrangeUnstack
            case kVK_ANSI_S, kVK_Escape: return .arrangeStack // Back to the normal keys.
            default: return nil
            }
        }

        switch keyCode {
        case kVK_LeftArrow, kVK_RightArrow:
            let right = keyCode == kVK_RightArrow
            if command && !option && !shift { return right ? .arrangeToEnd : .arrangeToStart }
            if option && !command && !shift { return right ? .arrangeRight : .arrangeLeft }
            if shift && !option && !command { return right ? .arrangeWider : .arrangeNarrower }
            return plain ? (right ? .focusColumnRight : .focusColumnLeft) : nil
        case kVK_UpArrow, kVK_DownArrow:
            let up = keyCode == kVK_UpArrow
            if shift && !option && !command { return up ? .arrangeTaller : .arrangeShorter }
            return plain ? (up ? .focusStackUp : .focusStackDown) : nil
        case kVK_ANSI_S: return plain ? .arrangeStack : nil
        case kVK_Escape: return .arrangeDone
        default: return nil
        }
    }
}

private final class KeyTakingPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

private final class ArrangeHUDView: NSView {
    var tiles: [ArrangeHUD.Tile] = [] { didSet { needsDisplay = true } }
    var focused: Int? { didSet { needsDisplay = true } }
    /// After S: the hints row asks which side to stack with.
    var stackPrompt = false { didSet { needsDisplay = true } }
    /// Shown in the header for a moment when a key had nothing to do.
    var note: String? { didSet { needsDisplay = true } }
    var onReorder: ((Int, Int) -> Void)?
    var onSelect: ((Int) -> Void)?
    var onStack: ((Int, Int) -> Void)?
    var onKey: ((HotKeyCenter.Action) -> Void)?
    /// Height keys only mean something for a window in a stack.
    var showsHeight = false { didSet { needsDisplay = true } }

    override var acceptsFirstResponder: Bool { true }

    override func keyDown(with event: NSEvent) {
        // A held key repeats; only arrows may (to keep moving), everything else acts once.
        let keyCode = Int(event.keyCode)
        let isArrow = [kVK_LeftArrow, kVK_RightArrow, kVK_UpArrow, kVK_DownArrow].contains(keyCode)
        guard !event.isARepeat || isArrow else { return }
        if let action = ArrangeHUD.action(keyCode: keyCode, flags: event.modifierFlags, stacking: stackPrompt) {
            onKey?(action)
        }
    }

    private static let unit: CGFloat = 150
    private var tileHeight: CGFloat { showsPreviews ? 96 : 64 }
    private var unit: CGFloat { showsPreviews ? 170 : Self.unit }
    private var showsPreviews: Bool { tiles.contains { $0.parts.contains { $0.preview != nil } } }
    private static let gap: CGFloat = 8
    private static let padding: CGFloat = 16
    private static let header: CGFloat = 26
    private static let footer: CGFloat = 38
    private var normalHints: [(key: String, label: String)] {
        [("← →", "Focus"), ("⌥← ⌥→", "Move"), ("⌘← ⌘→", "To the start / end"), ("⇧← ⇧→", "Width"),
         ("⇧↑ ⇧↓", "Height"), ("S", "Stack"), ("esc", "Done")]
    }
    private static let stackHints: [(key: String, label: String)] = [
        ("← →", "Stack with the left / right column"), ("D", "Unstack"), ("S", "Back"), ("esc", "Back"),
    ]
    private var hints: [(key: String, label: String)] { stackPrompt ? Self.stackHints : normalHints }

    private var dragging: (index: Int, location: CGPoint)?
    private var dropIndex: Int?
    /// The tile a dragged tile is over the middle of: letting go stacks into it.
    private var stackTarget: Int?
    /// Widest the bar may get (the screen, less a margin); tiles past it hide behind "…".
    var maxWidth: CGFloat = .greatestFiniteMagnitude { didSet { needsDisplay = true } }
    /// First visible tile, kept between updates so the run only slides when focus leaves it.
    private var firstVisible = 0
    private static let marker: CGFloat = 40

    override var isFlipped: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    private var tileWidths: [CGFloat] { tiles.map { max(54, unit * CGFloat($0.width)) } }

    private var visible: Range<Int> {
        let range = ArrangeHUD.visibleRange(
            widths: tileWidths, focused: focused, previousStart: firstVisible,
            available: maxWidth - Self.padding * 2, gap: Self.gap, marker: Self.marker
        )
        return range
    }

    /// The tiles' row: visible tiles plus a marker on each side that hides some.
    private var rowWidth: CGFloat {
        let range = visible
        let widths = tileWidths[range]
        var width = widths.reduce(0, +) + Self.gap * CGFloat(max(range.count - 1, 0))
        if range.lowerBound > 0 { width += Self.marker + Self.gap }
        if range.upperBound < tiles.count { width += Self.marker + Self.gap }
        return width
    }

    override var fittingSize: NSSize {
        firstVisible = visible.lowerBound
        let width = min(max(rowWidth, hintsWidth) + Self.padding * 2, max(maxWidth, hintsWidth + Self.padding * 2))
        return NSSize(width: width, height: Self.header + tileHeight + 14 + Self.footer)
    }

    private var hintsWidth: CGFloat {
        hints.map { keyText($0.key).size().width + 14 + 6 + labelText($0.label).size().width }.reduce(0, +)
            + 16 * CGFloat(hints.count - 1)
    }

    /// Visible tiles with their column index, plus the "…" markers' frames.
    private func layoutRow() -> (tiles: [(index: Int, rect: CGRect)], leading: CGRect?, trailing: CGRect?) {
        let range = visible
        var x = (bounds.width - rowWidth) / 2
        var leading: CGRect?
        if range.lowerBound > 0 {
            leading = CGRect(x: x, y: Self.header, width: Self.marker, height: tileHeight)
            x += Self.marker + Self.gap
        }
        var rects: [(Int, CGRect)] = []
        for index in range {
            rects.append((index, CGRect(x: x, y: Self.header, width: tileWidths[index], height: tileHeight)))
            x += tileWidths[index] + Self.gap
        }
        let trailing = range.upperBound < tiles.count
            ? CGRect(x: x, y: Self.header, width: Self.marker, height: tileHeight) : nil
        return (rects, leading, trailing)
    }

    override func draw(_ dirtyRect: NSRect) {
        let volt = NSColor(named: "Volt") ?? .systemGreen
        NSColor(calibratedWhite: 0.11, alpha: 0.92).setFill()
        let background = NSBezierPath(roundedRect: bounds, xRadius: 16, yRadius: 16)
        background.fill()
        NSColor.white.withAlphaComponent(0.12).setStroke()
        background.stroke()

        if let note {
            NSAttributedString(string: note, attributes: [
                .font: NSFont.systemFont(ofSize: 11, weight: .semibold),
                .foregroundColor: NSColor(named: "Volt") ?? .systemGreen,
            ]).draw(at: CGPoint(x: Self.padding, y: 8))
        } else {
            labelText("Drag a tile to reorder", alpha: 0.35).draw(at: CGPoint(x: Self.padding, y: 8))
        }

        let row = layoutRow()
        for (marker, hidden) in [(row.leading, visible.lowerBound), (row.trailing, tiles.count - visible.upperBound)] {
            guard let marker else { continue }
            let text = labelText("… \(hidden)", alpha: 0.6)
            text.draw(at: CGPoint(x: marker.midX - text.size().width / 2, y: marker.midY - text.size().height / 2))
        }
        let rects = row.tiles
        for (index, rect) in rects {
            let isFocused = index == focused
            let isDragged = index == dragging?.index
            let shape = NSBezierPath(roundedRect: rect, xRadius: 10, yRadius: 10)
            (isFocused ? volt.withAlphaComponent(0.15) : NSColor.white.withAlphaComponent(0.08)).setFill()
            shape.fill()
            shape.lineWidth = isFocused ? 2 : 1
            (isFocused ? volt : NSColor.white.withAlphaComponent(0.12)).setStroke()
            shape.stroke()
            let alpha: CGFloat = isDragged ? 0.3 : 1
            drawTileContent(index: index, in: rect, alpha: alpha, isFocused: isFocused)
        }

        if let stackTarget, let rect = rects.first(where: { $0.index == stackTarget })?.rect {
            let ring = NSBezierPath(roundedRect: rect.insetBy(dx: -3, dy: -3), xRadius: 12, yRadius: 12)
            ring.lineWidth = 3
            volt.setStroke()
            ring.stroke()
            let label = NSAttributedString(string: "Stack", attributes: [
                .font: NSFont.systemFont(ofSize: 11, weight: .bold),
                .foregroundColor: NSColor(named: "Ink") ?? .black,
            ])
            let pill = CGRect(x: rect.midX - label.size().width / 2 - 8, y: rect.minY - 10, width: label.size().width + 16, height: 18)
            volt.setFill()
            NSBezierPath(roundedRect: pill, xRadius: 6, yRadius: 6).fill()
            label.draw(at: CGPoint(x: pill.minX + 8, y: pill.minY + 2))
        } else if let dropIndex, let dragging, dropIndex != dragging.index, dropIndex != dragging.index + 1 {
            let x: CGFloat = rects.first { $0.index == dropIndex }.map { $0.rect.minX - Self.gap / 2 }
                ?? (rects.last?.rect.maxX ?? 0) + Self.gap / 2
            volt.setFill()
            NSBezierPath(roundedRect: CGRect(x: x - 1.5, y: Self.header, width: 3, height: tileHeight), xRadius: 1.5, yRadius: 1.5).fill()
        }

        if let dragging, let rect = rects.first(where: { $0.index == dragging.index })?.rect {
            let lifted = CGRect(x: dragging.location.x - rect.width / 2, y: Self.header - 8, width: rect.width, height: rect.height)
            NSColor(calibratedWhite: 0.2, alpha: 0.95).setFill()
            NSBezierPath(roundedRect: lifted, xRadius: 10, yRadius: 10).fill()
            drawTileContent(index: dragging.index, in: lifted, alpha: 1, isFocused: dragging.index == focused)
        }

        // Key hints.
        let lineY = Self.header + tileHeight + 14
        NSColor.white.withAlphaComponent(0.08).setFill()
        CGRect(x: 0, y: lineY, width: bounds.width, height: 1).fill()
        var x = (bounds.width - hintsWidth) / 2
        for hint in hints {
            let key = keyText(hint.key)
            let keySize = key.size()
            let cap = CGRect(x: x, y: lineY + 10, width: keySize.width + 14, height: keySize.height + 4)
            NSColor.white.withAlphaComponent(0.85).setFill()
            NSBezierPath(roundedRect: cap, xRadius: 5, yRadius: 5).fill()
            key.draw(at: CGPoint(x: cap.minX + 7, y: cap.minY + 2))
            let label = labelText(hint.label)
            label.draw(at: CGPoint(x: cap.maxX + 6, y: cap.minY + 2))
            x = cap.maxX + 6 + label.size().width + 16
        }
    }

    private func drawTileContent(index: Int, in rect: CGRect, alpha: CGFloat, isFocused: Bool) {
        if showsPreviews {
            drawPreviewTile(index: index, in: rect, alpha: alpha, isFocused: isFocused)
            return
        }
        // Icons side by side: one for a lone window, two or three for a stack.
        let parts = tiles[index].parts
        let size: CGFloat = parts.count > 1 ? 20 : 24
        let spacing: CGFloat = 4
        let total = CGFloat(parts.count) * size + CGFloat(max(parts.count - 1, 0)) * spacing
        var x = rect.midX - total / 2
        for part in parts {
            part.icon?.draw(in: CGRect(x: x, y: rect.minY + 10 + (24 - size) / 2, width: size, height: size), from: .zero, operation: .sourceOver, fraction: alpha, respectFlipped: true, hints: nil)
            x += size + spacing
        }
        let volt = NSColor(named: "Volt") ?? .systemGreen
        let number = NSAttributedString(string: "\(index + 1)", attributes: [
            .font: NSFont.monospacedSystemFont(ofSize: 12, weight: .bold),
            .foregroundColor: (isFocused ? volt : NSColor.white.withAlphaComponent(0.7)).withAlphaComponent(alpha),
        ])
        number.draw(at: CGPoint(x: rect.midX - number.size().width / 2, y: rect.minY + 40))
    }

    /// Snapshots filling the tile (cropped to fit): one per window, stacked like the column, each with
    /// its app icon, and the column number in a badge.
    private func drawPreviewTile(index: Int, in rect: CGRect, alpha: CGFloat, isFocused: Bool) {
        let inner = rect.insetBy(dx: 4, dy: 4)
        let parts = tiles[index].parts
        let totalHeight = parts.map(\.height).reduce(0, +)
        var y = inner.minY
        for (row, part) in parts.enumerated() {
            let share = totalHeight > 0 ? part.height / totalHeight : 1 / Double(parts.count)
            let height = row == parts.count - 1 ? inner.maxY - y : (inner.height * CGFloat(share)).rounded() - 1
            let cell = CGRect(x: inner.minX, y: y, width: inner.width, height: max(height, 4))
            y = cell.maxY + 2

            NSGraphicsContext.saveGraphicsState()
            NSBezierPath(roundedRect: cell, xRadius: 6, yRadius: 6).addClip()
            NSColor(calibratedWhite: 0.12, alpha: 1).setFill()
            cell.fill()
            if let preview = part.preview, preview.size.width > 1, preview.size.height > 1 {
                let scale = max(cell.width / preview.size.width, cell.height / preview.size.height)
                let size = CGSize(width: preview.size.width * scale, height: preview.size.height * scale)
                // Top of the window (title bar, the part people recognise) stays in view.
                let drawRect = CGRect(x: cell.midX - size.width / 2, y: cell.minY, width: size.width, height: size.height)
                preview.draw(in: drawRect, from: .zero, operation: .sourceOver, fraction: alpha, respectFlipped: true, hints: nil)
            }
            NSGraphicsContext.restoreGraphicsState()
            if parts.count > 1 {
                part.icon?.draw(in: CGRect(x: cell.maxX - 20, y: cell.minY + 4, width: 16, height: 16), from: .zero, operation: .sourceOver, fraction: alpha, respectFlipped: true, hints: nil)
            }
        }

        let volt = NSColor(named: "Volt") ?? .systemGreen
        let number = NSAttributedString(string: "\(index + 1)", attributes: [
            .font: NSFont.monospacedSystemFont(ofSize: 11, weight: .bold),
            .foregroundColor: (isFocused ? volt : NSColor.white).withAlphaComponent(alpha),
        ])
        let badge = CGRect(x: rect.minX + 8, y: rect.maxY - 30, width: 18 + 5 + number.size().width + 9, height: 24)
        NSColor(calibratedWhite: 0.06, alpha: 0.85 * alpha).setFill()
        NSBezierPath(roundedRect: badge, xRadius: 7, yRadius: 7).fill()
        tiles[index].icon?.draw(in: CGRect(x: badge.minX + 3, y: badge.minY + 3, width: 18, height: 18), from: .zero, operation: .sourceOver, fraction: alpha, respectFlipped: true, hints: nil)
        number.draw(at: CGPoint(x: badge.minX + 26, y: badge.minY + 4))
    }

    private func keyText(_ string: String) -> NSAttributedString {
        NSAttributedString(string: string, attributes: [
            .font: NSFont.monospacedSystemFont(ofSize: 10, weight: .medium),
            .foregroundColor: NSColor(named: "Ink") ?? .black,
        ])
    }

    private func labelText(_ string: String, alpha: CGFloat = 0.55) -> NSAttributedString {
        NSAttributedString(string: string, attributes: [
            .font: NSFont.systemFont(ofSize: 11),
            .foregroundColor: NSColor.white.withAlphaComponent(alpha),
        ])
    }

    // MARK: Dragging tiles

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        guard let index = layoutRow().tiles.first(where: { $0.rect.contains(point) })?.index else { return }
        dragging = (index, point)
        dropIndex = nil
    }

    override func mouseDragged(with event: NSEvent) {
        guard var dragging else { return }
        dragging.location = convert(event.locationInWindow, from: nil)
        self.dragging = dragging
        let rects = layoutRow().tiles
        // Over the middle of another tile: stack into it. Near its sides or between tiles: reorder.
        stackTarget = rects.first { tile in
            tile.index != dragging.index
                && tile.rect.insetBy(dx: tile.rect.width * 0.25, dy: -12).contains(dragging.location)
        }?.index
        dropIndex = rects.first { dragging.location.x < $0.rect.midX }?.index ?? ((rects.last?.index ?? -1) + 1)
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        defer {
            dragging = nil
            dropIndex = nil
            stackTarget = nil
            needsDisplay = true
        }
        guard let dragging else { return }
        if let stackTarget {
            onStack?(dragging.index, stackTarget)
            return
        }
        guard let dropIndex else {
            onSelect?(dragging.index) // A click, not a drag.
            return
        }
        // Dropping between tiles: index among the others once the dragged one is taken out.
        let target = dropIndex > dragging.index ? dropIndex - 1 : dropIndex
        if target != dragging.index { onReorder?(dragging.index, target) }
    }
}

/// A Volt outline around the focused window with an "Arrange mode" badge on top.
@MainActor
final class FocusOutline {
    private let panel: NSPanel
    private let view = FocusOutlineView()

    init() {
        panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        panel.isReleasedWhenClosed = false
        panel.isOpaque = false
        panel.hasShadow = false
        panel.backgroundColor = .clear
        panel.ignoresMouseEvents = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenNone]
        panel.contentView = view
    }

    /// - Parameter frame: the window's frame in AppKit coordinates.
    func show(around frame: CGRect) {
        let badgeRoom: CGFloat = 18
        panel.setFrame(frame.insetBy(dx: -4, dy: -4).union(frame.offsetBy(dx: 0, dy: badgeRoom)), display: true)
        view.windowFrame = frame.offsetBy(dx: -panel.frame.minX, dy: -panel.frame.minY)
        panel.orderFrontRegardless()
    }

    func hide() {
        panel.orderOut(nil)
    }
}

private final class FocusOutlineView: NSView {
    var windowFrame: CGRect = .zero { didSet { needsDisplay = true } }

    override func draw(_ dirtyRect: NSRect) {
        let volt = NSColor(named: "Volt") ?? .systemGreen
        let outline = NSBezierPath(roundedRect: windowFrame.insetBy(dx: -1.5, dy: -1.5), xRadius: 12, yRadius: 12)
        outline.lineWidth = 3
        volt.setStroke()
        outline.stroke()

        let text = NSAttributedString(string: "⇄  Arrange mode", attributes: [
            .font: NSFont.systemFont(ofSize: 13, weight: .bold),
            .foregroundColor: NSColor(named: "Ink") ?? .black,
        ])
        let size = text.size()
        let badge = CGRect(
            x: windowFrame.midX - size.width / 2 - 12,
            y: windowFrame.maxY - size.height / 2 - 6,
            width: size.width + 24,
            height: size.height + 12
        )
        volt.setFill()
        NSBezierPath(roundedRect: badge, xRadius: 9, yRadius: 9).fill()
        text.draw(at: CGPoint(x: badge.minX + 12, y: badge.minY + 6))
    }
}
