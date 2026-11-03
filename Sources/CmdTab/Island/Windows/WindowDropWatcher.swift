import AppKit
import Observation

/// Where a window dropped on the island goes.
enum WindowDropLayout: Int, CaseIterable, Identifiable {
    case leftHalf, rightHalf, fill, centre

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .leftHalf: "Left half"
        case .rightHalf: "Right half"
        case .fill: "Fill"
        case .centre: "Centre"
        }
    }

    var symbol: String {
        switch self {
        case .leftHalf: "rectangle.lefthalf.filled"
        case .rightHalf: "rectangle.righthalf.filled"
        case .fill: "rectangle.fill"
        case .centre: "rectangle.center.inset.filled"
        }
    }

    /// The frame in `area` (any coordinate space with y down or up: only x and sizes differ).
    func frame(in area: CGRect) -> CGRect {
        switch self {
        case .leftHalf: CGRect(x: area.minX, y: area.minY, width: (area.width / 2).rounded(), height: area.height)
        case .rightHalf:
            CGRect(x: area.minX + (area.width / 2).rounded(), y: area.minY, width: area.width - (area.width / 2).rounded(), height: area.height)
        case .fill: area
        case .centre:
            CGRect(x: area.minX + area.width / 6, y: area.minY + area.height / 12, width: area.width * 2 / 3, height: area.height * 5 / 6).integral
        }
    }

    /// Which layout the pointer is over, splitting `rect` into equal columns.
    static func at(x: CGFloat, in rect: CGRect) -> WindowDropLayout? {
        guard rect.width > 0, x >= rect.minX, x <= rect.maxX else { return nil }
        let index = min(Int((x - rect.minX) / rect.width * CGFloat(allCases.count)), allCases.count - 1)
        return WindowDropLayout(rawValue: index)
    }
}

/// Drag a window up to the island and let go on a layout. Watches mouse drags (only while a button
/// is held, so nothing runs otherwise) and acts when the dragged window is pinned at the top.
@MainActor
@Observable
final class WindowDropWatcher {
    /// While a window is held over the island: the layout under the pointer.
    private(set) var isActive = false
    private(set) var selection: WindowDropLayout?

    /// Where the island's picker is on screen, set by the island (AppKit coordinates).
    @ObservationIgnored var pickerRect: CGRect = .zero
    @ObservationIgnored var screenPadding: () -> Double = { 0 }
    @ObservationIgnored private var monitors: [Any] = []
    @ObservationIgnored private var window: AXUIElement?

    /// How close to the top of the screen the pointer must be.
    static let reach: CGFloat = 40

    func start() {
        guard monitors.isEmpty else { return }
        if let drag = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDragged, handler: { [weak self] _ in
            MainActor.assumeIsolated { self?.dragged() }
        }) { monitors.append(drag) }
        if let up = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseUp, handler: { [weak self] _ in
            MainActor.assumeIsolated { self?.released() }
        }) { monitors.append(up) }
    }

    func stop() {
        monitors.forEach(NSEvent.removeMonitor)
        monitors.removeAll()
        reset()
    }

    private func dragged() {
        let pointer = NSEvent.mouseLocation
        // Once the picker shows, the pointer can go down to it: it sits below the top band.
        let overPicker = isActive && pickerRect.insetBy(dx: -24, dy: -24).contains(pointer)
        guard let screen = NSScreen.under(pointer),
              overPicker || pointer.y >= screen.frame.maxY - Self.reach else {
            if isActive { reset() }
            return
        }
        if !isActive {
            guard let window = Self.draggedWindow(under: pointer, on: screen) else { return }
            self.window = window
            isActive = true
        }
        let layout = WindowDropLayout.at(x: pointer.x, in: pickerRect)
        if layout != selection { selection = layout }
    }

    private func released() {
        defer { reset() }
        guard isActive, let window, let layout = selection,
              let screen = NSScreen.under(NSEvent.mouseLocation) else { return }
        let frame = ScreenGeometry.accessibilityRect(fromAppKit: screen.frame)
        let visible = ScreenGeometry.accessibilityRect(fromAppKit: screen.visibleFrame)
        let area = ScreenPadding.area(frame: frame, visible: visible, padding: screenPadding())
        // Let the drag finish first, or the app puts the window back where the mouse let go.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            window.setFrame(layout.frame(in: area))
        }
    }

    private func reset() {
        isActive = false
        selection = nil
        window = nil
    }

    /// The front app's focused window, if it's pinned against the top of the screen under the pointer:
    /// that's a window being dragged up (macOS stops windows at the menu bar).
    private static func draggedWindow(under pointer: CGPoint, on screen: NSScreen) -> AXUIElement? {
        guard let app = NSWorkspace.shared.frontmostApplication,
              app.processIdentifier != ProcessInfo.processInfo.processIdentifier else { return nil }
        let element = AXUIElementCreateApplication(app.processIdentifier)
        guard let window: AXUIElement = element.value(of: kAXFocusedWindowAttribute), let frame = window.frame else { return nil }
        let top = ScreenGeometry.accessibilityRect(fromAppKit: screen.visibleFrame).minY
        let x = ScreenGeometry.accessibilityPoint(fromAppKit: pointer).x
        guard abs(frame.minY - top) < 12, x >= frame.minX, x <= frame.maxX else { return nil }
        return window
    }
}
