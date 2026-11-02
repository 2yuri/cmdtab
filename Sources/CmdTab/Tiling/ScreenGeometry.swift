import AppKit
import ApplicationServices

/// Accessibility places windows in global coordinates with the origin at the top left of the main
/// display and y growing downwards; AppKit uses the bottom left and y growing upwards.
enum ScreenGeometry {
    private static var primaryHeight: CGFloat {
        NSScreen.screens.first?.frame.maxY ?? 0
    }

    static func accessibilityRect(fromAppKit rect: CGRect) -> CGRect {
        CGRect(x: rect.minX, y: primaryHeight - rect.maxY, width: rect.width, height: rect.height)
    }

    static func appKitRect(fromAccessibility rect: CGRect) -> CGRect {
        CGRect(x: rect.minX, y: primaryHeight - rect.maxY, width: rect.width, height: rect.height)
    }

    static func accessibilityPoint(fromAppKit point: CGPoint) -> CGPoint {
        CGPoint(x: point.x, y: primaryHeight - point.y)
    }

    /// The screen a window (in Accessibility coordinates) is mostly on.
    static func screen(containing rect: CGRect) -> NSScreen? {
        let centre = CGPoint(x: rect.midX, y: rect.midY)
        return NSScreen.screens.first { accessibilityRect(fromAppKit: $0.frame).contains(centre) }
    }
}

extension AXUIElement {
    /// The window's frame in Accessibility coordinates.
    var frame: CGRect? {
        let attributes = values(of: [kAXPositionAttribute, kAXSizeAttribute])
        guard let positionValue = attributes[kAXPositionAttribute], let sizeValue = attributes[kAXSizeAttribute]
        else { return nil }
        var position = CGPoint.zero
        var size = CGSize.zero
        // swiftlint:disable force_cast
        guard AXValueGetValue(positionValue as! AXValue, .cgPoint, &position),
              AXValueGetValue(sizeValue as! AXValue, .cgSize, &size)
        else { return nil }
        // swiftlint:enable force_cast
        return CGRect(origin: position, size: size)
    }

    /// Moves and resizes the window. Position goes first and last: some apps clamp their size
    /// against the screen edge, so the second move puts the window back where it was asked to go.
    func setFrame(_ frame: CGRect) {
        var origin = frame.origin
        var size = frame.size
        guard let position = AXValueCreate(.cgPoint, &origin), let dimensions = AXValueCreate(.cgSize, &size) else { return }
        AXUIElementSetAttributeValue(self, kAXPositionAttribute as CFString, position)
        AXUIElementSetAttributeValue(self, kAXSizeAttribute as CFString, dimensions)
        AXUIElementSetAttributeValue(self, kAXPositionAttribute as CFString, position)
    }

    /// Moves the window without resizing it: one call, so it slides cleanly during animations.
    func setPosition(_ point: CGPoint) {
        var origin = point
        guard let position = AXValueCreate(.cgPoint, &origin) else { return }
        AXUIElementSetAttributeValue(self, kAXPositionAttribute as CFString, position)
    }

    func isSettable(_ attribute: String) -> Bool {
        var settable = DarwinBoolean(false)
        return AXUIElementIsAttributeSettable(self, attribute as CFString, &settable) == .success && settable.boolValue
    }
}

/// Screen padding: every window stays a set distance from the screen edges.
enum ScreenPadding {
    /// The area windows may use, in Accessibility coordinates. Padding is measured from the screen's
    /// edges, so the menu bar counts towards it and the space looks even all round; it is never less
    /// than the menu bar, and windows still stay clear of the Dock.
    ///
    /// - Parameters:
    ///   - frame: the whole screen; `visible`: without menu bar and Dock (both Accessibility coordinates).
    static func area(frame: CGRect, visible: CGRect, padding: CGFloat) -> CGRect {
        guard padding > 0 else { return visible }
        let inset = max(padding, minimum(frame: frame, visible: visible))
        let area = frame.insetBy(dx: inset, dy: inset).intersection(visible)
        return area.isNull ? visible : area
    }

    /// The smallest padding: the menu bar's height (zero when it hides itself).
    static func minimum(frame: CGRect, visible: CGRect) -> CGFloat {
        max(visible.minY - frame.minY, 0)
    }

    @MainActor
    static func area(of screen: NSScreen, padding: CGFloat) -> CGRect {
        area(
            frame: ScreenGeometry.accessibilityRect(fromAppKit: screen.frame),
            visible: ScreenGeometry.accessibilityRect(fromAppKit: screen.visibleFrame),
            padding: padding
        )
    }

    /// The menu bar height of the main screen, the least padding the setting offers.
    @MainActor
    static var minimumForMainScreen: CGFloat {
        guard let screen = NSScreen.main else { return 24 }
        return minimum(
            frame: ScreenGeometry.accessibilityRect(fromAppKit: screen.frame),
            visible: ScreenGeometry.accessibilityRect(fromAppKit: screen.visibleFrame)
        )
    }

    /// The frame moved (and shrunk if needed) to sit inside `area`, or `nil` if it already does.
    static func fitted(_ frame: CGRect, inside area: CGRect, tolerance: CGFloat = 1) -> CGRect? {
        guard area.width > 0, area.height > 0 else { return nil }
        let inside = frame.minX >= area.minX - tolerance && frame.maxX <= area.maxX + tolerance
            && frame.minY >= area.minY - tolerance && frame.maxY <= area.maxY + tolerance
        guard !inside else { return nil }
        let width = min(frame.width, area.width)
        let height = min(frame.height, area.height)
        let x = min(max(frame.minX, area.minX), area.maxX - width)
        let y = min(max(frame.minY, area.minY), area.maxY - height)
        return CGRect(x: x, y: y, width: width, height: height)
    }
}
