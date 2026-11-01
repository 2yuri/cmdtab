import ServiceManagement
import os

@MainActor
enum LaunchAtLogin {
    private static let logger = Logger(subsystem: "dev.yuri.CmdTab", category: "LaunchAtLogin")

    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    static func setEnabled(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            logger.error("Could not update login item: \(error.localizedDescription, privacy: .public)")
        }
    }
}
