import SwiftUI

struct SwitcherPane: View {
    @Bindable var preferences: Preferences
    let screenRecording: ScreenRecordingPermission

    var body: some View {
        Form {
            Section {
                Picker(selection: $preferences.spaceScope) {
                    Text("Current Desktop").tag(SpaceScope.currentSpace)
                    Text("All Desktops").tag(SpaceScope.allSpaces)
                } label: {
                    Text("Show windows from")
                    Text("With several displays, includes the desktop shown on each.")
                }
                .pickerStyle(.segmented)

                Toggle(isOn: $preferences.groupsWindowsByApp) {
                    Text("Group windows by app")
                    Text("One tile per app, like the macOS switcher. Picking it brings all its windows forward.")
                }

                Toggle("Minimized windows", isOn: $preferences.showsMinimizedWindows)
                Toggle("Windows of hidden apps", isOn: $preferences.showsHiddenAppWindows)
            } header: {
                Text("Windows")
            } footer: {
                Text("Minimized and hidden windows are listed last, dimmed.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Appearance") {
                Picker(selection: $preferences.switcherStyle) {
                    Text("Icons").tag(SwitcherStyle.icons)
                    Text("Previews").tag(SwitcherStyle.previews)
                    Text("Titles").tag(SwitcherStyle.titles)
                } label: {
                    Text("Style")
                    Text(styleDescription)
                }
                .pickerStyle(.segmented)
                .onChange(of: preferences.switcherStyle) { _, style in
                    if style == .previews && !screenRecording.isGranted { screenRecording.requestAccess() }
                }

                if preferences.switcherStyle == .previews && !screenRecording.isGranted {
                    screenRecordingHint("Until then, the switcher shows app icons.")
                }

                Picker("Size", selection: $preferences.switcherSize) {
                    Text("Small").tag(SwitcherSize.small)
                    Text("Medium").tag(SwitcherSize.medium)
                    Text("Large").tag(SwitcherSize.large)
                }
                .pickerStyle(.segmented)

                Picker("Theme", selection: $preferences.theme) {
                    Text("System").tag(AppTheme.system)
                    Text("Light").tag(AppTheme.light)
                    Text("Dark").tag(AppTheme.dark)
                }
                .pickerStyle(.segmented)

                Toggle(isOn: $preferences.previewsSelectedWindow) {
                    Text("Preview selected window")
                    Text("Shows the selected window where it is on screen. With Screen Recording, the window itself; otherwise an outline.")
                }

                if preferences.previewsSelectedWindow && !screenRecording.isGranted {
                    screenRecordingHint("Until then, the preview is an outline.")
                }

                Toggle(isOn: $preferences.quickSwitch) {
                    Text("Quick switch")
                    Text("A quick ⌘⇥ tap switches without showing the panel.")
                }
            }

            Section("Search") {
                Toggle(isOn: $preferences.opensInSearchMode) {
                    Text("Open in search mode")
                    Text("The search bar is always there: let go of ⌘ and type. Otherwise press ⌘F while the switcher is open.")
                }
            }
        }
        .formStyle(.grouped)
        .onAppear { screenRecording.refresh() }
    }

    private var styleDescription: String {
        switch preferences.switcherStyle {
        case .icons: "App icons, like the macOS switcher."
        case .previews: "A snapshot of each window. Needs Screen Recording, used only while the switcher is open."
        case .titles: "A compact list of window titles."
        }
    }

    private func screenRecordingHint(_ fallback: String) -> some View {
        LabeledContent {
            Button("Open Screen Recording Settings") { screenRecording.requestAccess() }
        } label: {
            Label("Screen Recording is off", systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text("Turn on CmdTab in the list. macOS may ask you to reopen CmdTab. \(fallback)")
        }
    }
}
