import SwiftUI

struct GeneralPane: View {
    @Bindable var preferences: Preferences
    @State private var launchesAtLogin = LaunchAtLogin.isEnabled

    var body: some View {
        Form {
            Section("Startup") {
                Toggle(isOn: $launchesAtLogin) {
                    Text("Launch at login")
                    Text("Start CmdTab when you log in to your Mac.")
                }
                .onChange(of: launchesAtLogin) { _, enabled in
                    LaunchAtLogin.setEnabled(enabled)
                    launchesAtLogin = LaunchAtLogin.isEnabled
                }

                Toggle(isOn: $preferences.showsMenuBarIcon) {
                    Text("Show menu bar icon")
                    Text("When hidden, open CmdTab again to bring it back.")
                }
            }

            Section {
                EnergyCard(permissionCount: preferences.wantsScreenRecording ? 2 : 1)
            } footer: {
                HStack {
                    Spacer()
                    Button("Quit CmdTab") { NSApp.terminate(nil) }
                }
                .padding(.top, 8)
            }
        }
        .formStyle(.grouped)
    }
}

/// Why CmdTab is light on battery, in three numbers.
private struct EnergyCard: View {
    let permissionCount: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 10) {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.volt)
                    .frame(width: 28, height: 28)
                    .overlay(Image(systemName: "leaf.fill").font(.system(size: 13)).foregroundStyle(Color.ink))
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Idle means idle").fontWeight(.semibold)
                    Text("No background work. CmdTab wakes only when you press ⌘⇥ and builds the window list on the spot.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Divider()

            HStack {
                stat("0%", "CPU while idle")
                stat("0", "captures while idle")
                stat("\(permissionCount)", permissionCount == 1 ? "permission" : "permissions")
            }
        }
        .padding(.vertical, 4)
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(.system(size: 24, weight: .bold, design: .rounded))
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}
