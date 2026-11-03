import SwiftUI

struct ShortcutsPane: View {
    @Bindable var preferences: Preferences

    var body: some View {
        Form {
            Section("Switch windows") {
                LabeledContent("Next window") { KeyCaps(keys: ["⌘", "⇥"]) }
                LabeledContent("Previous window") { KeyCaps(keys: ["⌘", "⇧", "⇥"]) }
                Toggle(isOn: $preferences.replacesNativeSwitcher) {
                    Text("Replace the macOS app switcher")
                    Text("Turns the built-in ⌘⇥ off while CmdTab runs and back on when it quits.")
                }
            }

            Section("While the switcher is open") {
                LabeledContent("Back one") { KeyCaps(keys: ["⌘", "`"]) }
                LabeledContent("Move selection") { KeyCaps(keys: ["←", "→", "↑", "↓"]) }
                LabeledContent {
                    KeyCaps(keys: ["↩"])
                } label: {
                    Text("Open selected window")
                    Text("Or just release ⌘.")
                }
                LabeledContent("Cancel") { KeyCaps(keys: ["esc"]) }
                LabeledContent {
                    KeyCaps(keys: ["⌘", "F"])
                } label: {
                    Text("Search")
                    Text("Type to filter by window title or app. ⇥ to move, ↩ to open.")
                }
            }

            Section("Act on the selected window") {
                LabeledContent {
                    KeyCaps(keys: ["⌘", "W"])
                } label: {
                    Text("Close window")
                    Text("Its tile disappears; the switcher stays open.")
                }
                LabeledContent("Minimize window") { KeyCaps(keys: ["⌘", "M"]) }
                LabeledContent {
                    KeyCaps(keys: ["⌘", "Q"])
                } label: {
                    Text("Quit app")
                    Text("Quits the app the selected window belongs to.")
                }
            }
        }
        .formStyle(.grouped)
    }
}
