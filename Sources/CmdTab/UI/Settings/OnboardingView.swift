import SwiftUI

/// First launch: explains and requests the Accessibility permission.
struct OnboardingView: View {
    let permission: AccessibilityPermission
    let onLater: () -> Void

    private let steps = [
        "Click Open System Settings",
        "Turn on CmdTab under Accessibility",
        "Come back. ⌘⇥ starts working right away",
    ]

    var body: some View {
        VStack(spacing: 18) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 72, height: 72)
                .accessibilityHidden(true)

            VStack(spacing: 6) {
                Text("Let CmdTab switch your windows")
                    .font(.title2.weight(.semibold))
                Text("CmdTab needs Accessibility access to read window titles and bring the one you pick to the front. That's the only permission it will ever ask for.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(spacing: 0) {
                ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                    HStack(spacing: 12) {
                        Text("\(index + 1)")
                            .font(.system(size: 11, weight: .semibold, design: .monospaced))
                            .foregroundStyle(Color.accentColor)
                            .frame(width: 22, height: 22)
                            .background(Color.accentColor.opacity(0.15), in: Circle())
                        Text(step)
                        Spacer()
                    }
                    .padding(.vertical, 10)
                    if index < steps.count - 1 { Divider() }
                }
            }
            .padding(.horizontal, 14)
            .background(.background.secondary, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(.separator))

            HStack(spacing: 8) {
                Label("Waiting for access…", systemImage: "hourglass")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                Spacer()
                Button("Later", action: onLater)
                    .keyboardShortcut(.cancelAction)
                Button("Open System Settings") { permission.requestAccess() }
                    .buttonStyle(ProminentButtonStyle())
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(.horizontal, 32)
        .padding(.top, 12)
        .padding(.bottom, 28)
        .frame(width: 440)
    }
}
