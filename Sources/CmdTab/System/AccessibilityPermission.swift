import AppKit
import ApplicationServices
import Observation

/// Accessibility is the only permission CmdTab needs: it reads window titles and raises windows.
/// (No Screen Recording, no Input Monitoring, no microphone.)
@MainActor
@Observable
final class AccessibilityPermission {
    /// Kept current by the system's accessibility notification: no polling.
    private(set) var isGranted = AXIsProcessTrusted()

    @ObservationIgnored private var observer: NSObjectProtocol?

    init() {
        observer = DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name("com.apple.accessibility.api"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            // The trust flag is updated slightly after the notification is posted.
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .milliseconds(500))
                self?.refresh()
            }
        }
    }

    func refresh() {
        let granted = AXIsProcessTrusted()
        if granted != isGranted { isGranted = granted }
    }

    /// Adds CmdTab to the Accessibility list (with the system prompt) and opens that list.
    func requestAccess() {
        // Literal value of `kAXTrustedCheckOptionPrompt` (a mutable C global, not concurrency-safe in Swift 6).
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
        openSystemSettings()
    }

    func openSystemSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
        else { return }
        NSWorkspace.shared.open(url)
    }
}
