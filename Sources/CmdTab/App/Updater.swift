import Foundation
import Observation
@preconcurrency import Sparkle

/// Auto update through Sparkle (Settings → About).
///
/// Sparkle asks the GitHub release feed for the latest version once a day, at most. The download is
/// installed only if its EdDSA signature matches the key built into the app and it is signed with the
/// same Developer ID. No system profile is ever sent (`SUEnableSystemProfiling` is off).
@MainActor
@Observable
final class Updater: NSObject {
    /// The newer version a check found, until it is installed.
    private(set) var availableVersion: String?
    private(set) var lastCheck: Date?

    @ObservationIgnored private var controller: SPUStandardUpdaterController!

    override init() {
        super.init()
        controller = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: self, userDriverDelegate: self)
        lastCheck = updater.lastUpdateCheckDate
    }

    private var updater: SPUUpdater { controller.updater }

    var automaticallyChecks: Bool {
        get {
            access(keyPath: \.automaticallyChecks)
            return updater.automaticallyChecksForUpdates
        }
        set {
            withMutation(keyPath: \.automaticallyChecks) {
                updater.automaticallyChecksForUpdates = newValue
            }
        }
    }

    var canCheck: Bool { updater.canCheckForUpdates }

    /// Checks now and shows Sparkle's window: the release notes and Install, or "You're up to date".
    func checkNow() {
        controller.checkForUpdates(nil)
    }

    fileprivate func found(_ version: String?) {
        availableVersion = version
        lastCheck = updater.lastUpdateCheckDate ?? Date()
    }
}

extension Updater: SPUUpdaterDelegate {
    nonisolated func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        let version = item.displayVersionString
        MainActor.assumeIsolated { found(version) }
    }

    nonisolated func updaterDidNotFindUpdate(_ updater: SPUUpdater) {
        MainActor.assumeIsolated { found(nil) }
    }
}

extension Updater: SPUStandardUserDriverDelegate {
    /// CmdTab lives in the menu bar, so a scheduled check that finds an update waits quietly in
    /// Settings → About instead of popping a window over whatever the user is doing.
    nonisolated var supportsGentleScheduledUpdateReminders: Bool { true }

    nonisolated func standardUserDriverShouldHandleShowingScheduledUpdate(
        _ update: SUAppcastItem,
        andInImmediateFocus immediateFocus: Bool
    ) -> Bool {
        immediateFocus
    }
}
