import SwiftUI

struct AboutPane: View {
    let preferences: Preferences
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

            Text("© 2026 Yuri Miguel")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
