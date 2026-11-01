import CoreGraphics
import Foundation

/// The handful of facts we need about a window from `CGWindowListCopyWindowInfo`.
/// Reading this list needs no permission at all (titles would need Screen Recording,
/// which is exactly what we avoid — they come from Accessibility instead).
struct WindowServerEntry: Equatable {
    let windowID: CGWindowID
    let pid: pid_t
    let layer: Int
    /// Global screen coordinates, origin at the top-left of the main display.
    let bounds: CGRect
    let isOnScreen: Bool

    var size: CGSize { bounds.size }

    init(windowID: CGWindowID, pid: pid_t, layer: Int, size: CGSize, origin: CGPoint = .zero, isOnScreen: Bool = true) {
        self.windowID = windowID
        self.pid = pid
        self.layer = layer
        self.bounds = CGRect(origin: origin, size: size)
        self.isOnScreen = isOnScreen
    }

    init?(_ info: [String: Any]) {
        guard let windowID = info[kCGWindowNumber as String] as? CGWindowID,
              let pid = info[kCGWindowOwnerPID as String] as? pid_t,
              let layer = info[kCGWindowLayer as String] as? Int,
              let boundsInfo = info[kCGWindowBounds as String] as? NSDictionary,
              let bounds = CGRect(dictionaryRepresentation: boundsInfo)
        else { return nil }
        self.init(
            windowID: windowID,
            pid: pid,
            layer: layer,
            size: bounds.size,
            origin: bounds.origin,
            isOnScreen: info[kCGWindowIsOnscreen as String] as? Bool ?? false
        )
    }
}
