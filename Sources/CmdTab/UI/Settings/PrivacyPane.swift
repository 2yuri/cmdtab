import SwiftUI

struct PrivacyPane: View {
    let permission: AccessibilityPermission
    let screenRecording: ScreenRecordingPermission
    let preferences: Preferences
    var updater: Updater?

    var body: some View {
        Form {
            Section {
                row(
                    "Accessibility",
                    detail: "Reads window titles and brings the window you pick to the front.",
                    status: permission.isGranted ? "Allowed" : "Not allowed",
                    isPositive: permission.isGranted
                )
                screenRecordingRow
                row("Microphone & Camera", status: "Never requested")
                networkRow
            } header: {
                Text("CmdTab asks only for what it needs to switch windows. Nothing leaves your Mac.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .textCase(nil)
                    .padding(.bottom, 4)
            } footer: {
                HStack {
                    Spacer()
                    Button("Open Privacy Settings") { permission.openSystemSettings() }
                }
                .padding(.top, 8)
            }
        }
        .formStyle(.grouped)
        .onAppear {
            permission.refresh()
            screenRecording.refresh()
        }
    }

    @ViewBuilder
    private var networkRow: some View {
        if updater?.automaticallyChecks == true {
            row(
                "Network",
                detail: "One update check a day, to GitHub. No analytics, no telemetry. Turn it off in About.",
                status: "Update check only"
            )
        } else {
            row("Network", detail: "No analytics, no telemetry, no update checks.", status: "No connections")
        }
    }

    @ViewBuilder
    private var screenRecordingRow: some View {
        if preferences.wantsScreenRecording {
            row(
                "Screen Recording",
                detail: "For previews only: snapshots are taken while the switcher is open, kept in memory, never saved or sent.",
                status: screenRecording.isGranted ? "Allowed" : "Not allowed",
                isPositive: screenRecording.isGranted
            )
        } else if screenRecording.isGranted {
            row(
                "Screen Recording",
                detail: "Allowed, but not used: previews are off. You can revoke it in System Settings.",
                status: "Not used"
            )
        } else {
            row(
                "Screen Recording",
                detail: "Previews are off, so nothing on your screen is ever captured.",
                status: "Not used"
            )
        }
    }

    private func row(_ title: String, detail: String? = nil, status: String, isPositive: Bool = false) -> some View {
        LabeledContent {
            StatusPill(title: status, isPositive: isPositive)
        } label: {
            Text(title)
            if let detail { Text(detail) }
        }
    }
}
