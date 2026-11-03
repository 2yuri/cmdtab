import SwiftUI

/// Settings → Island: the live strip in the notch and the modules it shows.
struct IslandPane: View {
    @Bindable var preferences: Preferences
    @State private var claudeLimits = ClaudeSettings.hasStatusLine

    private var modules: [Binding<IslandModuleSetting>] {
        $preferences.islandModules.filter { IslandModule.available.contains($0.wrappedValue.module) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Text("Island")
                Text("NEW")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .tracking(0.8)
                    .foregroundStyle(Color.ink)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(Color.volt, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            }
            .font(.title2.weight(.semibold))
            .accessibilityAddTraits(.isHeader)
            .padding(.horizontal, 20)
            .padding(.top, 12)

            Form {
                Section("Island") {
                    Toggle(isOn: $preferences.islandEnabled) {
                        Text("Show the CmdTab Island")
                        Text("Lives in the notch. Stays the notch's size until something happens.")
                    }
                    Group {
                        Toggle(isOn: $preferences.islandOpensOnHover) {
                            Text("Open when the pointer rests on it")
                            Text("Off: open it with a click instead.")
                        }
                        Toggle("Show the session limit while closed", isOn: $preferences.islandShowsLimit)
                        Picker("Show on", selection: $preferences.islandScreen) {
                            ForEach(IslandScreen.allCases, id: \.self) { Text($0.label).tag($0) }
                        }
                        .pickerStyle(.segmented)
                    }
                    .disabled(!preferences.islandEnabled)
                }

                Section {
                    ForEach(modules) { $setting in
                        ModuleRow(setting: $setting)
                    }
                    .onMove(perform: move)
                } header: {
                    Text("Modules")
                } footer: {
                    Text("Drag to change the order of the tabs.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .disabled(!preferences.islandEnabled)

                Section("Shelf and weather") {
                    Toggle(isOn: $preferences.islandWatchesNewFiles) {
                        Text("Add new downloads and screenshots")
                        Text("They land on the Shelf for 24 hours. macOS asks once for the Downloads and Desktop folders.")
                    }
                    .disabled(!preferences.isIslandModuleOn(.shelf))
                    LabeledContent {
                        Text(preferences.islandWeatherPlace.map { "\($0.name), \($0.region)" } ?? "Not set")
                            .foregroundStyle(.secondary)
                    } label: {
                        Text("Weather city")
                        Text("Pick it from the Weather tab. Only the city name is sent to Open-Meteo, never your location.")
                    }
                    .disabled(!preferences.isIslandModuleOn(.weather))
                }
                .disabled(!preferences.islandEnabled)

                Section {
                    LabeledContent {
                        StatusPill(title: ClaudeSettings.isClaudeInstalled ? "Connected" : "Not found", isPositive: ClaudeSettings.isClaudeInstalled)
                    } label: {
                        Text("Claude Code")
                        Text("Found in ~/.claude. Sessions and when it needs you.")
                    }
                    Toggle(isOn: $claudeLimits) {
                        Text("Claude Code limits")
                        Text("Read from its status line. Your own status line keeps working.")
                    }
                    .onChange(of: claudeLimits) { _, on in
                        ClaudeSettings.setStatusLine(on)
                        claudeLimits = ClaudeSettings.hasStatusLine
                    }
                    .disabled(!ClaudeSettings.isClaudeInstalled)
                    LabeledContent {
                        StatusPill(title: CodexReader.isInstalled ? "Connected" : "Not found", isPositive: CodexReader.isInstalled)
                    } label: {
                        Text("Codex")
                        Text("Found in ~/.codex.")
                    }
                    Toggle(isOn: $preferences.islandApprovals) {
                        Text("Approve and deny from the island")
                        Text("Claude Code waits for your Allow or Deny. Adds a small hook to its settings.")
                    }
                    .onChange(of: preferences.islandApprovals) { _, on in
                        ClaudeSettings.setApprovalHook(on)
                    }
                    .disabled(!ClaudeSettings.isClaudeInstalled)
                    Toggle(isOn: $preferences.islandNotifies) {
                        Text("Notify when an agent finishes or needs you")
                        Text("The island grows for a moment with Open.")
                    }
                } header: {
                    Text("Agents")
                } footer: {
                    Text("Sessions are read from the files each tool keeps on your Mac, only when they change.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .disabled(!preferences.islandEnabled || !preferences.isIslandModuleOn(.agents))
            }
            .formStyle(.grouped)
        }
    }

    private func move(from source: IndexSet, to destination: Int) {
        let visible = modules.map(\.wrappedValue.module)
        var reordered = visible
        reordered.move(fromOffsets: source, toOffset: destination)
        // Modules not shown keep their place after the visible ones.
        let rest = preferences.islandModules.filter { !visible.contains($0.module) }
        let byModule = Dictionary(uniqueKeysWithValues: preferences.islandModules.map { ($0.module, $0) })
        preferences.islandModules = reordered.compactMap { byModule[$0] } + rest
    }
}

private struct ModuleRow: View {
    @Binding var setting: IslandModuleSetting

    var body: some View {
        Toggle(isOn: $setting.isOn) {
            HStack(spacing: 10) {
                Image(systemName: "line.3.horizontal")
                    .foregroundStyle(.tertiary)
                    .font(.system(size: 11))
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(Color.accentColor.opacity(0.18))
                    .frame(width: 26, height: 26)
                    .overlay(Image(systemName: setting.module.symbol).font(.system(size: 12)).foregroundStyle(Color.accentColor))
                VStack(alignment: .leading, spacing: 2) {
                    Text(setting.module.title)
                    Text(setting.module.detail).font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }
}
