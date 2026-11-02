import AppKit

/// Brings a chosen window to the front.
@MainActor
enum WindowActivator {
    /// A grouped tile brings all of the app's visible windows forward, like the native switcher,
    /// with the most recent one on top and focused.
    static func activate(_ item: SwitcherItem) {
        for window in item.others.reversed() where !window.isDimmed {
            if let element = window.element {
                AXUIElementPerformAction(element, kAXRaiseAction as CFString)
            }
        }
        activate(item.primary)
    }

    static func activate(_ window: SwitcherWindow) {
        let app = NSRunningApplication(processIdentifier: window.pid)

        if window.isAppHidden {
            app?.unhide()
        }
        if window.isMinimized, let element = window.element {
            AXUIElementSetAttributeValue(element, kAXMinimizedAttribute as CFString, kCFBooleanFalse)
        }

        let element = window.element
            ?? PrivateAPI.windowElements(pid: window.pid, windowIDs: [window.windowID], searching: 5000)[window.windowID]
        let focused = PrivateAPI.focusWindow(window.windowID, pid: window.pid)
        var raise = AXError.noValue
        if let element {
            AXUIElementSetAttributeValue(element, kAXMainAttribute as CFString, kCFBooleanTrue)
            raise = AXUIElementPerformAction(element, kAXRaiseAction as CFString)
        }
        // Activating the whole app is only a fallback: it brings forward the app's window on the
        // current Space, which would undo a switch to a full-screen app.
        var activated = false
        if !focused && raise != .success {
            activated = app?.activate() ?? false
        }
        Log.activation.debug("""
            activate \(window.appName, privacy: .public) #\(window.windowID) pid=\(window.pid) \
            focus=\(focused) raise=\(raise.rawValue) fallbackActivate=\(activated)
            """)
    }
}
