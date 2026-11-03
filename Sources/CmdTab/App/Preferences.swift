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
        static let scrollLockEnabled = "scrollLockEnabled"
        static let defaultColumnWidth = "defaultColumnWidth"
        static let defaultStackHeight = "defaultStackHeight"
        static let centreMode = "centreMode"
        static let tilingPadding = "tilingPadding"
        static let tilingGap = "tilingGap"
        static let keepsWindowsOffEdges = "keepsWindowsOffEdges"
        static let animatesScrolling = "animatesScrolling"
        static let animationSpeed = "animationSpeed"
        static let wrapsAround = "wrapsAround"
        static let floatsSystemApps = "floatsSystemApps"
        static let floatingApps = "floatingApps"
        static let hidesFloatingApps = "hidesFloatingApps"
        /// Replaced by `dragToStack`; read once to migrate.
        static let legacyStacksByDragging = "stacksByDragging"
        static let dragToStack = "dragToStack"
        static let arrangePreviews = "arrangePreviews"
        static let dimsOtherWindows = "dimsOtherWindows"
        static let dimAmount = "dimAmount"
        static let rememberedSizes = "rememberedSizes"
        static let islandEnabled = "islandEnabled"
        static let islandOpensOnHover = "islandOpensOnHover"
        static let islandShowsLimit = "islandShowsLimit"
        static let islandScreen = "islandScreen"
        static let islandModules = "islandModules"
        static let islandApprovals = "islandApprovals"
        static let islandNotifies = "islandNotifies"
        static let islandCities = "islandCities"
        static let islandWeatherPlace = "islandWeatherPlace"
        static let islandWatchesNewFiles = "islandWatchesNewFiles"

        static let all = [
            spaceScope, showsMinimizedWindows, showsHiddenAppWindows, switcherSize,
            theme, quickSwitch, replacesNativeSwitcher, showsMenuBarIcon, switcherStyle, groupsWindowsByApp, opensInSearchMode, legacyReleaseAction, exceptions,
            previewsSelectedWindow, legacyShowsWindowPreviews,
            scrollLockEnabled, defaultColumnWidth, defaultStackHeight, centreMode, tilingPadding, tilingGap,
            keepsWindowsOffEdges, animatesScrolling, animationSpeed, wrapsAround, floatsSystemApps, floatingApps, hidesFloatingApps, legacyStacksByDragging, dragToStack, arrangePreviews, dimsOtherWindows, dimAmount, rememberedSizes,
            islandEnabled, islandOpensOnHover, islandShowsLimit, islandScreen, islandModules, islandApprovals, islandNotifies,
            islandCities, islandWeatherPlace, islandWatchesNewFiles,
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


    // MARK: Tiling (beta)

    /// Scroll Lock: windows on the current desktop become columns on a strip that scrolls with focus.
    var scrollLockEnabled: Bool { didSet { defaults.set(scrollLockEnabled, forKey: Key.scrollLockEnabled) } }
    var defaultColumnWidth: ColumnWidth { didSet { defaults.set(defaultColumnWidth.rawValue, forKey: Key.defaultColumnWidth) } }
    var defaultStackHeight: StackHeight { didSet { defaults.set(defaultStackHeight.rawValue, forKey: Key.defaultStackHeight) } }
    /// The strip slides smoothly when focus moves; off, it jumps.
    var animatesScrolling: Bool { didSet { defaults.set(animatesScrolling, forKey: Key.animatesScrolling) } }
    /// 0.5 (half as fast) to 2 (twice as fast); scales every slide and scroll.
    var animationSpeed: Double { didSet { defaults.set(animationSpeed, forKey: Key.animationSpeed) } }
    /// ⌃⌥← on the first column goes to the last one, and back.
    var wrapsAround: Bool { didSet { defaults.set(wrapsAround, forKey: Key.wrapsAround) } }
    var centreMode: CentreMode { didSet { defaults.set(centreMode.rawValue, forKey: Key.centreMode) } }
    /// Screen padding: every window stays `tilingPadding` away from the screen edges, with or
    /// without Scroll Lock.
    var keepsWindowsOffEdges: Bool { didSet { defaults.set(keepsWindowsOffEdges, forKey: Key.keepsWindowsOffEdges) } }
    /// Space around the windows, where the desktop shows through.
    var tilingPadding: Double { didSet { defaults.set(tilingPadding, forKey: Key.tilingPadding) } }
    var tilingGap: Double { didSet { defaults.set(tilingGap, forKey: Key.tilingGap) } }
    var dimsOtherWindows: Bool { didSet { defaults.set(dimsOtherWindows, forKey: Key.dimsOtherWindows) } }
    /// 0…1, how dark the layer behind the focused window is.
    var dimAmount: Double { didSet { defaults.set(dimAmount, forKey: Key.dimAmount) } }
    /// Finder, System Settings and the other apps that come with macOS stay out of Scroll Lock.
    var floatsSystemApps: Bool { didSet { defaults.set(floatsSystemApps, forKey: Key.floatsSystemApps) } }
    /// Apps the user chose to keep out of Scroll Lock.
    var floatingApps: [FloatingApp] {
        didSet { defaults.set(try? JSONEncoder().encode(floatingApps), forKey: Key.floatingApps) }
    }
    /// Arrange mode's tiles show window snapshots (Screen Recording, only while Arrange mode is on).
    var arrangePreviews: Bool { didSet { defaults.set(arrangePreviews, forKey: Key.arrangePreviews) } }
    /// When dropping a window on the middle of another column stacks them.
    var dragToStack: DragToStack { didSet { defaults.set(dragToStack.rawValue, forKey: Key.dragToStack) } }
    /// Going back to a window on the strip hides (⌘H) floating apps, so they don't sit on top of it.
    var hidesFloatingApps: Bool { didSet { defaults.set(hidesFloatingApps, forKey: Key.hidesFloatingApps) } }
    var rememberedSizes: [RememberedSize] {
        didSet { defaults.set(try? JSONEncoder().encode(rememberedSizes), forKey: Key.rememberedSizes) }
    }

    // MARK: Island

    /// The live strip in the notch (a pill under the menu bar on screens without one).
    var islandEnabled: Bool { didSet { defaults.set(islandEnabled, forKey: Key.islandEnabled) } }
    /// Off: the island opens with a click.
    var islandOpensOnHover: Bool { didSet { defaults.set(islandOpensOnHover, forKey: Key.islandOpensOnHover) } }
    /// While an agent works, the closed island shows how much of its session limit is used.
    var islandShowsLimit: Bool { didSet { defaults.set(islandShowsLimit, forKey: Key.islandShowsLimit) } }
    var islandScreen: IslandScreen { didSet { defaults.set(islandScreen.rawValue, forKey: Key.islandScreen) } }
    /// Tabs in order, each on or off. Every module starts off.
    var islandModules: [IslandModuleSetting] {
        didSet { defaults.set(try? JSONEncoder().encode(islandModules), forKey: Key.islandModules) }
    }
    /// Claude Code asks CmdTab before showing its own permission prompt.
    var islandApprovals: Bool { didSet { defaults.set(islandApprovals, forKey: Key.islandApprovals) } }
    /// The island grows for a moment when an agent finishes or needs you.
    var islandNotifies: Bool { didSet { defaults.set(islandNotifies, forKey: Key.islandNotifies) } }

    /// World clock cities, in order. The first two show beside the notch when the island is open.
    var islandCities: [WorldCity] {
        didSet { defaults.set(try? JSONEncoder().encode(islandCities), forKey: Key.islandCities) }
    }
    /// The city weather is asked for; `nil` until you pick one.
    var islandWeatherPlace: WeatherPlace? {
        didSet { defaults.set(try? JSONEncoder().encode(islandWeatherPlace), forKey: Key.islandWeatherPlace) }
    }
    /// New downloads and screenshots land on the Shelf.
    var islandWatchesNewFiles: Bool { didSet { defaults.set(islandWatchesNewFiles, forKey: Key.islandWatchesNewFiles) } }

    func isIslandModuleOn(_ module: IslandModule) -> Bool {
        islandEnabled && islandModules.contains { $0.module == module && $0.isOn }
    }

    /// The tabs shown when the island opens, in the user's order.
    var islandTabs: [IslandModule] {
        islandModules.filter { $0.isOn && $0.module.hasTab && IslandModule.available.contains($0.module) }.map(\.module)
    }

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
        scrollLockEnabled = Self.boolValue(defaults, Key.scrollLockEnabled, default: false)
        defaultColumnWidth = Self.enumValue(defaults, Key.defaultColumnWidth, default: .twoThirds)
        defaultStackHeight = Self.enumValue(defaults, Key.defaultStackHeight, default: .half)
        centreMode = Self.enumValue(defaults, Key.centreMode, default: .whenOverflowing)
        tilingPadding = defaults.object(forKey: Key.tilingPadding) as? Double ?? 32
        tilingGap = defaults.object(forKey: Key.tilingGap) as? Double ?? 12
        keepsWindowsOffEdges = Self.boolValue(defaults, Key.keepsWindowsOffEdges, default: false)
        animatesScrolling = Self.boolValue(defaults, Key.animatesScrolling, default: true)
        animationSpeed = defaults.object(forKey: Key.animationSpeed) as? Double ?? 1
        wrapsAround = Self.boolValue(defaults, Key.wrapsAround, default: false)
        floatsSystemApps = Self.boolValue(defaults, Key.floatsSystemApps, default: true)
        hidesFloatingApps = Self.boolValue(defaults, Key.hidesFloatingApps, default: true)
        arrangePreviews = Self.boolValue(defaults, Key.arrangePreviews, default: true)
        dragToStack = Self.enumValue(
            defaults,
            Key.dragToStack,
            default: defaults.object(forKey: Key.legacyStacksByDragging) as? Bool == false ? .off : .inArrangeMode
        )
        floatingApps = defaults.data(forKey: Key.floatingApps)
            .flatMap { try? JSONDecoder().decode([FloatingApp].self, from: $0) } ?? []
        dimsOtherWindows = Self.boolValue(defaults, Key.dimsOtherWindows, default: false)
        dimAmount = defaults.object(forKey: Key.dimAmount) as? Double ?? 0.4
        rememberedSizes = defaults.data(forKey: Key.rememberedSizes)
            .flatMap { try? JSONDecoder().decode([RememberedSize].self, from: $0) } ?? []
        islandEnabled = Self.boolValue(defaults, Key.islandEnabled, default: false)
        islandOpensOnHover = Self.boolValue(defaults, Key.islandOpensOnHover, default: true)
        islandShowsLimit = Self.boolValue(defaults, Key.islandShowsLimit, default: true)
        islandScreen = Self.enumValue(defaults, Key.islandScreen, default: .builtIn)
        islandModules = IslandModuleSetting.normalized(
            defaults.data(forKey: Key.islandModules)
                .flatMap { try? JSONDecoder().decode([IslandModuleSetting].self, from: $0) } ?? []
        )
        islandApprovals = Self.boolValue(defaults, Key.islandApprovals, default: false)
        islandNotifies = Self.boolValue(defaults, Key.islandNotifies, default: true)
        islandCities = defaults.data(forKey: Key.islandCities)
            .flatMap { try? JSONDecoder().decode([WorldCity].self, from: $0) } ?? [.local]
        islandWeatherPlace = defaults.data(forKey: Key.islandWeatherPlace)
            .flatMap { try? JSONDecoder().decode(WeatherPlace.self, from: $0) }
        islandWatchesNewFiles = Self.boolValue(defaults, Key.islandWatchesNewFiles, default: true)
    }

    // MARK: Remembered sizes

    /// The padding windows keep from the screen edges; zero while Screen padding is off.
    var screenPadding: Double { keepsWindowsOffEdges ? tilingPadding : 0 }

    func rememberedSize(for bundleID: String) -> RememberedSize? {
        rememberedSizes.first { $0.bundleID == bundleID }
    }

    func remember(width: ColumnWidth? = nil, height: StackHeight? = nil, bundleID: String, name: String) {
        var size = rememberedSize(for: bundleID) ?? RememberedSize(bundleID: bundleID, name: name)
        if let width { size.width = width }
        if let height { size.height = height }
        if let index = rememberedSizes.firstIndex(where: { $0.bundleID == bundleID }) {
            rememberedSizes[index] = size
        } else {
            rememberedSizes.append(size)
        }
    }

    func forgetSize(of bundleID: String) {
        rememberedSizes.removeAll { $0.bundleID == bundleID }
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
        scrollLockEnabled = fresh.scrollLockEnabled
        defaultColumnWidth = fresh.defaultColumnWidth
        defaultStackHeight = fresh.defaultStackHeight
        centreMode = fresh.centreMode
        tilingPadding = fresh.tilingPadding
        tilingGap = fresh.tilingGap
        keepsWindowsOffEdges = fresh.keepsWindowsOffEdges
        animatesScrolling = fresh.animatesScrolling
        animationSpeed = fresh.animationSpeed
        wrapsAround = fresh.wrapsAround
        floatsSystemApps = fresh.floatsSystemApps
        hidesFloatingApps = fresh.hidesFloatingApps
        dragToStack = fresh.dragToStack
        arrangePreviews = fresh.arrangePreviews
        floatingApps = fresh.floatingApps
        dimsOtherWindows = fresh.dimsOtherWindows
        dimAmount = fresh.dimAmount
        rememberedSizes = fresh.rememberedSizes
        islandEnabled = fresh.islandEnabled
        islandOpensOnHover = fresh.islandOpensOnHover
        islandShowsLimit = fresh.islandShowsLimit
        islandScreen = fresh.islandScreen
        islandModules = fresh.islandModules
        islandApprovals = fresh.islandApprovals
        islandNotifies = fresh.islandNotifies
        islandCities = fresh.islandCities
        islandWeatherPlace = fresh.islandWeatherPlace
        islandWatchesNewFiles = fresh.islandWatchesNewFiles
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
