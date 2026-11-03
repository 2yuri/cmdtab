#if DEBUG
import AppKit

/// Debug-only launch mode: `CMDTAB_PREVIEW=settings:dark:privacy` (or `onboarding:light`,
/// `switcher:dark:large`, …) opens a single
/// window and skips everything else, so it never touches ⌘⇥ or a running copy of CmdTab.
struct DesignPreview {
    enum Screen: String { case settings, onboarding, switcher, island }

    let screen: Screen
    let theme: AppTheme
    let pane: SettingsPane
    let switcherSize: SwitcherSize
    /// `island:dark:clock` opens the island on that tab and keeps it open.
    var islandTab: IslandModule?
    /// `island:dark:columns` (or `stack`) shows a tiled window held over the island.
    var islandOption = ""

    var appearance: NSAppearance? { theme.appearance }

    static var requested: DesignPreview? {
        guard let value = ProcessInfo.processInfo.environment["CMDTAB_PREVIEW"] else { return nil }
        let parts = value.split(separator: ":").map(String.init)
        guard let screen = parts.first.flatMap(Screen.init(rawValue:)) else { return nil }
        let theme = parts.count > 1 ? AppTheme(rawValue: parts[1]) ?? .system : .system
        let option = parts.count > 2 ? parts[2] : ""
        return DesignPreview(
            screen: screen,
            theme: theme,
            pane: SettingsPane(rawValue: option) ?? .general,
            switcherSize: SwitcherSize(rawValue: option) ?? .medium,
            islandTab: IslandModule(rawValue: option),
            islandOption: option
        )
    }
}
#endif
