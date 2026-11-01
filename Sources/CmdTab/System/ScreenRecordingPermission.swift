import AppKit
import CoreGraphics
import Observation

/// Screen Recording is optional: it's only needed for window previews.
@MainActor
@Observable
final class ScreenRecordingPermission {
    private(set) var isGranted = CGPreflightScreenCaptureAccess()

    /// macOS posts no notification for this permission; call when the answer matters (Settings opening,
    /// the switcher revealing previews).
    func refresh() {
        let granted = CGPreflightScreenCaptureAccess()
        if granted != isGranted { isGranted = granted }
    }

    /// Shows the system prompt once (which adds CmdTab to the list) and opens the Screen Recording list.
    func requestAccess() {
        if !CGRequestScreenCaptureAccess() {
            openSystemSettings()
        }
        refresh()
    }

    func openSystemSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")
        else { return }
        NSWorkspace.shared.open(url)
    }
}
