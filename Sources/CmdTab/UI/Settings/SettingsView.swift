import SwiftUI

enum SettingsPane: String, CaseIterable, Identifiable {
    case general, switcher, shortcuts, tiling, island, exceptions, privacy, about

    var id: Self { self }

    var title: String {
        switch self {
        case .general: "General"
        case .switcher: "Switcher"
        case .shortcuts: "Shortcuts"
        case .tiling: "Tiling"
        case .island: "Island"
        case .exceptions: "Exceptions"
        case .privacy: "Privacy"
        case .about: "About"
        }
    }

    var symbol: String {
        switch self {
        case .general: "gearshape"
        case .switcher: "square.grid.2x2"
        case .shortcuts: "command"
        case .tiling: "rectangle.split.3x1"
        case .island: "capsule.fill"
        case .exceptions: "eye.slash"
        case .privacy: "lock.shield"
        case .about: "info.circle"
        }
    }
}

struct SettingsView: View {
    private static let sidebarWidth: CGFloat = 200

    @Bindable var preferences: Preferences
    let permission: AccessibilityPermission
    let screenRecording: ScreenRecordingPermission
    let updater: Updater?
    @State private var selection: SettingsPane?

    init(
        preferences: Preferences,
        permission: AccessibilityPermission,
        screenRecording: ScreenRecordingPermission,
        updater: Updater? = nil,
        initialPane: SettingsPane = .general
    ) {
        self.preferences = preferences
        self.permission = permission
        self.screenRecording = screenRecording
        self.updater = updater
        _selection = State(initialValue: initialPane)
    }

    var body: some View {
        let current = selection ?? .general
        HStack(spacing: 0) {
            // Custom rows instead of `List` selection: the system highlight puts white text on the
            // accent colour, which is unreadable on Volt in dark mode.
            VStack(spacing: 2) {
                ForEach(SettingsPane.allCases) { pane in
                    SidebarRow(pane: pane, isSelected: pane == current) { selection = pane }
                }
                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.top, 44) // Clears the traffic lights.
            .frame(width: Self.sidebarWidth)
            .frame(maxHeight: .infinity)
            .background(SidebarMaterial().ignoresSafeArea())

            Divider().ignoresSafeArea()

            VStack(alignment: .leading, spacing: 0) {
                // Tiling and Island draw their own titles, with a tag.
                if current != .tiling && current != .island {
                    Text(current.title)
                        .font(.title2.weight(.semibold))
                        .padding(.horizontal, 20)
                        .padding(.top, 12)
                        .accessibilityAddTraits(.isHeader)
                }
                pane(current)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .ignoresSafeArea(edges: .top)
        .frame(width: 720, height: 520)
    }

    @ViewBuilder
    private func pane(_ pane: SettingsPane) -> some View {
        switch pane {
        case .general: GeneralPane(preferences: preferences)
        case .switcher: SwitcherPane(preferences: preferences, screenRecording: screenRecording)
        case .shortcuts: ShortcutsPane(preferences: preferences)
        case .tiling: TilingPane(preferences: preferences)
        case .island: IslandPane(preferences: preferences)
        case .exceptions: ExceptionsPane(preferences: preferences)
        case .privacy: PrivacyPane(permission: permission, screenRecording: screenRecording, preferences: preferences, updater: updater)
        case .about: AboutPane(preferences: preferences, updater: updater)
        }
    }
}

private struct SidebarRow: View {
    let pane: SettingsPane
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: pane.symbol)
                    .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                    .frame(width: 18)
                Text(pane.title)
                    .lineLimit(1)
                    .fontWeight(isSelected ? .semibold : .regular)
                    .foregroundStyle(.primary)
                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
            .background(
                isSelected ? Color.accentColor.opacity(0.16) : .clear,
                in: RoundedRectangle(cornerRadius: 7, style: .continuous)
            )
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// The native translucent sidebar background.
private struct SidebarMaterial: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .sidebar
        view.blendingMode = .behindWindow
        view.state = .followsWindowActiveState
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}
