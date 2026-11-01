import Foundation
import Observation

enum SpaceScope: String, CaseIterable {
    /// Only windows on the Space(s) currently visible — one per display.
    case currentSpace
    case allSpaces
}

enum SwitcherSize: String, CaseIterable {
    case small, medium, large
}

enum AppTheme: String, CaseIterable {
    case system, light, dark
}


/// An app treated specially (Settings → Exceptions).
struct AppException: Codable, Hashable, Identifiable {
    enum Rule: String, Codable, CaseIterable {
        /// Its windows never appear in the switcher.
        case hide
        /// While it is in front, ⌘⇥ is left to it (virtual machines, remote desktops).
        case leaveShortcut
    }

    var bundleID: String
    var name: String
    var rule: Rule

    var id: String { bundleID }
}

/// User settings, persisted in `UserDefaults` and observable by SwiftUI and AppKit alike.
@MainActor
@Observable
final class Preferences {
    private enum Key {
        static let spaceScope = "spaceScope"
        static let showsMinimizedWindows = "showsMinimizedWindows"
        static let showsHiddenAppWindows = "showsHiddenAppWindows"
        static let switcherSize = "switcherSize"
        static let theme = "theme"
        static let quickSwitch = "quickSwitch"
        static let replacesNativeSwitcher = "replacesNativeSwitcher"
        static let showsMenuBarIcon = "showsMenuBarIcon"
        static let switcherStyle = "switcherStyle"
        static let groupsWindowsByApp = "groupsWindowsByApp"
        static let opensInSearchMode = "opensInSearchMode"
        static let exceptions = "exceptions"
        /// Replaced by `opensInSearchMode`; read once to migrate.
        static let legacyReleaseAction = "releaseAction"
        static let previewsSelectedWindow = "previewsSelectedWindow"
        /// Replaced by `switcherStyle`; read once to migrate.
        static let legacyShowsWindowPreviews = "showsWindowPreviews"

        static let all = [
            spaceScope, showsMinimizedWindows, showsHiddenAppWindows, switcherSize,
            theme, quickSwitch, replacesNativeSwitcher, showsMenuBarIcon, switcherStyle, groupsWindowsByApp, opensInSearchMode, legacyReleaseAction, exceptions,
            previewsSelectedWindow, legacyShowsWindowPreviews,
        ]
    }

    @ObservationIgnored private let defaults: UserDefaults

    var spaceScope: SpaceScope { didSet { defaults.set(spaceScope.rawValue, forKey: Key.spaceScope) } }
    var showsMinimizedWindows: Bool { didSet { defaults.set(showsMinimizedWindows, forKey: Key.showsMinimizedWindows) } }
    var showsHiddenAppWindows: Bool { didSet { defaults.set(showsHiddenAppWindows, forKey: Key.showsHiddenAppWindows) } }
    var switcherSize: SwitcherSize { didSet { defaults.set(switcherSize.rawValue, forKey: Key.switcherSize) } }
    var theme: AppTheme { didSet { defaults.set(theme.rawValue, forKey: Key.theme) } }
    /// A quick ⌘⇥ tap switches without flashing the panel.
    var quickSwitch: Bool { didSet { defaults.set(quickSwitch, forKey: Key.quickSwitch) } }
    /// When off, CmdTab steps aside and the macOS switcher handles ⌘⇥ again.
    var replacesNativeSwitcher: Bool { didSet { defaults.set(replacesNativeSwitcher, forKey: Key.replacesNativeSwitcher) } }
    var showsMenuBarIcon: Bool { didSet { defaults.set(showsMenuBarIcon, forKey: Key.showsMenuBarIcon) } }
    /// Icons, window snapshots (needs Screen Recording) or a list of titles.
    var switcherStyle: SwitcherStyle { didSet { defaults.set(switcherStyle.rawValue, forKey: Key.switcherStyle) } }
    /// The search bar is there from the start, and letting go of ⌘ starts typing instead of switching.
    var opensInSearchMode: Bool { didSet { defaults.set(opensInSearchMode, forKey: Key.opensInSearchMode) } }
    var exceptions: [AppException] {
        didSet { defaults.set(try? JSONEncoder().encode(exceptions), forKey: Key.exceptions) }
    }
    /// Highlights the selected window where it sits on screen (its snapshot with Screen Recording).
    var previewsSelectedWindow: Bool {
        didSet { defaults.set(previewsSelectedWindow, forKey: Key.previewsSelectedWindow) }
    }
    /// One tile per app instead of one per window, like the native switcher.
    var groupsWindowsByApp: Bool { didSet { defaults.set(groupsWindowsByApp, forKey: Key.groupsWindowsByApp) } }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        spaceScope = Self.enumValue(defaults, Key.spaceScope, default: .currentSpace)
        showsMinimizedWindows = Self.boolValue(defaults, Key.showsMinimizedWindows, default: true)
        showsHiddenAppWindows = Self.boolValue(defaults, Key.showsHiddenAppWindows, default: true)
        switcherSize = Self.enumValue(defaults, Key.switcherSize, default: .medium)
        theme = Self.enumValue(defaults, Key.theme, default: .system)
        quickSwitch = Self.boolValue(defaults, Key.quickSwitch, default: true)
        replacesNativeSwitcher = Self.boolValue(defaults, Key.replacesNativeSwitcher, default: true)
        showsMenuBarIcon = Self.boolValue(defaults, Key.showsMenuBarIcon, default: true)
        let legacyStyle: SwitcherStyle = Self.boolValue(defaults, Key.legacyShowsWindowPreviews, default: false)
            ? .previews : .icons
        switcherStyle = Self.enumValue(defaults, Key.switcherStyle, default: legacyStyle)
        opensInSearchMode = Self.boolValue(
            defaults,
            Key.opensInSearchMode,
            default: defaults.string(forKey: Key.legacyReleaseAction) == "search"
        )
        previewsSelectedWindow = Self.boolValue(defaults, Key.previewsSelectedWindow, default: false)
        exceptions = defaults.data(forKey: Key.exceptions)
            .flatMap { try? JSONDecoder().decode([AppException].self, from: $0) } ?? []
        groupsWindowsByApp = Self.boolValue(defaults, Key.groupsWindowsByApp, default: false)
    }

    /// Whether any enabled feature can use Screen Recording.
    var wantsScreenRecording: Bool {
        switcherStyle == .previews || previewsSelectedWindow
    }

    var windowFilter: WindowFilterOptions {
        WindowFilterOptions(
            scope: spaceScope,
            includesMinimized: showsMinimizedWindows,
            includesHiddenApps: showsHiddenAppWindows,
            excludedBundleIDs: bundleIDs(for: .hide)
        )
    }

    func bundleIDs(for rule: AppException.Rule) -> Set<String> {
        Set(exceptions.filter { $0.rule == rule }.map(\.bundleID))
    }

    /// Restores every setting to its default value.
    func reset() {
        for key in Key.all {
            defaults.removeObject(forKey: key)
        }
        let fresh = Preferences(defaults: defaults)
        spaceScope = fresh.spaceScope
        showsMinimizedWindows = fresh.showsMinimizedWindows
        showsHiddenAppWindows = fresh.showsHiddenAppWindows
        switcherSize = fresh.switcherSize
        theme = fresh.theme
        quickSwitch = fresh.quickSwitch
        replacesNativeSwitcher = fresh.replacesNativeSwitcher
        showsMenuBarIcon = fresh.showsMenuBarIcon
        switcherStyle = fresh.switcherStyle
        opensInSearchMode = fresh.opensInSearchMode
        exceptions = fresh.exceptions
        previewsSelectedWindow = fresh.previewsSelectedWindow
        groupsWindowsByApp = fresh.groupsWindowsByApp
    }

    private static func boolValue(_ defaults: UserDefaults, _ key: String, default value: Bool) -> Bool {
        defaults.object(forKey: key) as? Bool ?? value
    }

    private static func enumValue<T: RawRepresentable>(_ defaults: UserDefaults, _ key: String, default value: T) -> T
        where T.RawValue == String {
        guard let rawValue = defaults.string(forKey: key) else { return value }
        return T(rawValue: rawValue) ?? value
    }
}
