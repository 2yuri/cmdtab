import AppKit
import ApplicationServices

/// Accessibility notifications from other apps' windows: created, closed, focused, moved, resized.
///
/// Event-driven, like the rest of CmdTab: macOS calls back only when something happens, so a
/// desktop where nothing changes costs nothing.
@MainActor
final class AXWindowWatcher {
    enum Event {
        /// Something about the set of windows changed (opened, closed, minimized, hidden).
        case windowsChanged
        case focusChanged
        case moved(AXUIElement)
        case resized(AXUIElement)
    }

    var onEvent: ((Event) -> Void)?

    private var observers: [pid_t: AXObserver] = [:]
    /// Windows already registered for per-window notifications, by app.
    private var watchedWindows: [pid_t: Set<CGWindowID>] = [:]

    private static let appNotifications = [
        kAXWindowCreatedNotification,
        kAXFocusedWindowChangedNotification,
        kAXApplicationHiddenNotification,
        kAXApplicationShownNotification,
    ]
    private static let windowNotifications = [
        kAXUIElementDestroyedNotification,
        kAXWindowMovedNotification,
        kAXWindowResizedNotification,
        kAXWindowMiniaturizedNotification,
        kAXWindowDeminiaturizedNotification,
    ]

    func watch(_ pid: pid_t) {
        guard observers[pid] == nil else { return }
        var observer: AXObserver?
        guard AXObserverCreate(pid, axObserverCallback, &observer) == .success, let observer else { return }
        let app = AXUIElementCreateApplication(pid)
        let context = Unmanaged.passUnretained(self).toOpaque()
        for notification in Self.appNotifications {
            AXObserverAddNotification(observer, app, notification as CFString, context)
        }
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode)
        observers[pid] = observer
    }

    /// Per-window notifications have to be registered on each window once it exists.
    func watch(window element: AXUIElement, id: CGWindowID, pid: pid_t) {
        guard let observer = observers[pid], watchedWindows[pid, default: []].insert(id).inserted else { return }
        let context = Unmanaged.passUnretained(self).toOpaque()
        for notification in Self.windowNotifications {
            AXObserverAddNotification(observer, element, notification as CFString, context)
        }
    }

    func forgetWindow(_ id: CGWindowID, pid: pid_t) {
        watchedWindows[pid]?.remove(id)
    }

    func unwatch(_ pid: pid_t) {
        guard let observer = observers.removeValue(forKey: pid) else { return }
        CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode)
        watchedWindows[pid] = nil
    }

    func unwatchAll() {
        for pid in observers.keys { unwatch(pid) }
    }

    fileprivate func handle(_ notification: String, element: AXUIElement) {
        switch notification {
        case kAXFocusedWindowChangedNotification: onEvent?(.focusChanged)
        case kAXWindowMovedNotification: onEvent?(.moved(element))
        case kAXWindowResizedNotification: onEvent?(.resized(element))
        default: onEvent?(.windowsChanged)
        }
    }
}

/// Called on the main run loop, where the observers' sources were added.
private func axObserverCallback(
    _: AXObserver,
    _ element: AXUIElement,
    _ notification: CFString,
    _ context: UnsafeMutableRawPointer?
) {
    guard let context else { return }
    let watcher = Unmanaged<AXWindowWatcher>.fromOpaque(context).takeUnretainedValue()
    let name = notification as String
    // The callback runs on the main run loop, so the element never leaves the main thread.
    nonisolated(unsafe) let element = element
    MainActor.assumeIsolated {
        watcher.handle(name, element: element)
    }
}
