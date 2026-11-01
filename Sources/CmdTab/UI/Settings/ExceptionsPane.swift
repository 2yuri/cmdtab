import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct ExceptionsPane: View {
    @Bindable var preferences: Preferences
    @State private var selection: AppException.ID?

    var body: some View {
        Form {
            Section {
                if preferences.exceptions.isEmpty {
                    Text("No exceptions. Add an app with +.")
                        .foregroundStyle(.secondary)
                }
                ForEach($preferences.exceptions) { $exception in
                    ExceptionRow(exception: $exception, isSelected: selection == exception.id)
                        .contentShape(Rectangle())
                        .onTapGesture { selection = exception.id }
                }
            } header: {
                Text("Hide apps you never switch to, or leave ⌘⇥ alone while an app is in front — virtual machines and remote desktops use it themselves.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .textCase(nil)
                    .padding(.bottom, 4)
            } footer: {
                VStack(alignment: .leading, spacing: 10) {
                    ControlGroup {
                        Button { addApp() } label: { Image(systemName: "plus") }
                            .accessibilityLabel("Add app")
                        Button { removeSelected() } label: { Image(systemName: "minus") }
                            .accessibilityLabel("Remove selected app")
                            .disabled(selection == nil)
                    }
                    .fixedSize()

                    Text("Hide: the app's windows never appear in the switcher. Leave ⌘⇥: when this app is in front, ⌘⇥ goes to it instead of CmdTab.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .padding(.top, 6)
            }
        }
        .formStyle(.grouped)
    }

    private func addApp() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowsMultipleSelection = true
        panel.prompt = "Add"
        guard panel.runModal() == .OK else { return }

        for url in panel.urls {
            guard let bundleID = Bundle(url: url)?.bundleIdentifier,
                  !preferences.exceptions.contains(where: { $0.bundleID == bundleID })
            else { continue }
            let name = FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
            preferences.exceptions.append(AppException(bundleID: bundleID, name: name, rule: .hide))
            selection = bundleID
        }
    }

    private func removeSelected() {
        preferences.exceptions.removeAll { $0.id == selection }
        selection = nil
    }
}

private struct ExceptionRow: View {
    @Binding var exception: AppException
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(nsImage: Self.icon(for: exception.bundleID))
                .resizable()
                .frame(width: 28, height: 28)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text(exception.name)
                Text(exception.bundleID)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Picker("Rule for \(exception.name)", selection: $exception.rule) {
                Text("Hide").tag(AppException.Rule.hide)
                Text("Leave ⌘⇥").tag(AppException.Rule.leaveShortcut)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
        }
        .padding(.vertical, 2)
        .listRowBackground(isSelected ? Color.accentColor.opacity(0.16) : nil)
    }

    private static func icon(for bundleID: String) -> NSImage {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
            return NSWorkspace.shared.icon(for: .application)
        }
        return NSWorkspace.shared.icon(forFile: url.path)
    }
}
