import AppKit

/// ⌘W / ⌘M / ⌘Q on the selected window, without switching to it.
@MainActor
enum WindowActions {
    /// Presses the window's close button, so the app can still ask about unsaved changes.
    static func close(_ window: SwitcherWindow) -> Bool {
        guard let element = window.element,
              let button: AXUIElement = element.value(of: kAXCloseButtonAttribute)
        else { return false }
        // `.cannotComplete` usually means the app was busy closing (or quit with its last window)
        // and didn't answer in time; the press itself went through.
        let result = AXUIElementPerformAction(button, kAXPressAction as CFString)
        return result == .success || result == .cannotComplete
    }

    static func minimize(_ window: SwitcherWindow) -> Bool {
        guard let element = window.element, !window.isMinimized else { return false }
        return AXUIElementSetAttributeValue(element, kAXMinimizedAttribute as CFString, kCFBooleanTrue) == .success
    }

    /// A normal quit: the app can still ask to save.
    static func quit(_ window: SwitcherWindow) -> Bool {
        NSRunningApplication(processIdentifier: window.pid)?.terminate() ?? false
    }
}
