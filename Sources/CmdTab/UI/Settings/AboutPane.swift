import SwiftUI

struct AboutPane: View {
    let preferences: Preferences
    let updater: Updater?
    @State private var isConfirmingReset = false

    private var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "–"
        let build = info?["CFBundleVersion"] as? String ?? "–"
        return "Version \(short) (\(build))"
    }

    var body: some View {
        VStack(spacing: 14) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 96, height: 96)
                .accessibilityHidden(true)

            Image("Wordmark")
                .accessibilityLabel("CmdTab")

            Text(version)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.secondary)

            Text("A quiet ⌘⇥ for the windows on this desktop.")

            Button("Reset Settings…") { isConfirmingReset = true }
                .padding(.top, 8)
                .confirmationDialog("Reset all CmdTab settings?", isPresented: $isConfirmingReset) {
                    Button("Reset Settings", role: .destructive) { preferences.reset() }
                } message: {
                    Text("Every option goes back to its default. Launch at login is not changed.")
                }

            if let updater {
                UpdatesBox(updater: updater)
                    .padding(.top, 4)
            }

            Text("© 2026 Yuri Miguel")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Auto update: the daily check and what it last found.
private struct UpdatesBox: View {
    @Bindable var updater: Updater

    var body: some View {
        VStack(spacing: 0) {
            row {
                Text("Check for updates automatically")
                    .fontWeight(.medium)
                Text("Once a day. Only asks GitHub for the latest version; nothing about you is sent.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } control: {
                Toggle("", isOn: $updater.automaticallyChecks)
                    .toggleStyle(.switch)
                    .labelsHidden()
            }
            Divider()
            row {
                if let version = updater.availableVersion {
                    Text("Version \(version) is available")
                        .fontWeight(.medium)
                        .foregroundStyle(Color.accentColor)
                    Text("CmdTab reopens in a few seconds.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("You're up to date")
                        .fontWeight(.medium)
                    Text(lastChecked)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } control: {
                if updater.availableVersion != nil {
                    Button("Install & Relaunch") { updater.checkNow() }
                        .buttonStyle(.borderedProminent)
                } else {
                    Button("Check Now") { updater.checkNow() }
                        .disabled(!updater.canCheck)
                }
            }
        }
        .frame(width: 400)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.separator))
    }

    private var lastChecked: String {
        guard let date = updater.lastCheck else { return "Not checked yet." }
        let day = Calendar.current.isDateInToday(date)
            ? "today"
            : date.formatted(.dateTime.day().month(.abbreviated))
        return "Last checked \(day) at \(date.formatted(date: .omitted, time: .shortened))."
    }

    private func row(@ViewBuilder text: () -> some View, @ViewBuilder control: () -> some View) -> some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 2, content: text)
                .frame(maxWidth: .infinity, alignment: .leading)
            control()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
    }
}
