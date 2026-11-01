import AppKit

/// A window the user can switch to.
struct SwitcherWindow {
    let windowID: CGWindowID
    let pid: pid_t
    /// Identifies the app across processes (bundle ID, or the PID when there is none).
    let appKey: String
    /// `nil` when the window lives on another Space: macOS only exposes accessibility
    /// elements for windows on the current Space.
    let element: AXUIElement?
    let title: String
    let appName: String
    let icon: NSImage?
    var isMinimized: Bool
    let isAppHidden: Bool
    /// Where the window is, in global top-left-origin coordinates (`CGWindowListCopyWindowInfo`).
    var frame: CGRect = .zero
    /// Set when the window lives on a desktop other than the visible one ("All Desktops").
    var desktopNumber: Int?

    /// Minimized windows and windows of hidden apps are shown dimmed, like the native switcher.
    var isDimmed: Bool { isMinimized || isAppHidden }
}

/// One tile in the switcher: a single window, or every window of an app when grouping is on.
struct SwitcherItem {
    /// The window that is focused when the tile is picked: the group's most recent visible window.
    let primary: SwitcherWindow
    /// The rest of the group, most recent first.
    let others: [SwitcherWindow]

    var windows: [SwitcherWindow] { [primary] + others }
    var windowCount: Int { others.count + 1 }
    var title: String { others.isEmpty ? primary.title : primary.appName }
    var tooltip: String {
        if others.isEmpty {
            return primary.title == primary.appName ? primary.appName : "\(primary.appName) — \(primary.title)"
        }
        return ([primary.appName] + windows.map { "• \($0.title)" }).joined(separator: "\n")
    }
    /// Dimmed only when no window of the group is visible.
    var isDimmed: Bool { windows.allSatisfy(\.isDimmed) }

    static func items(from windows: [SwitcherWindow], groupedByApp: Bool) -> [SwitcherItem] {
        guard groupedByApp else { return windows.map { SwitcherItem(primary: $0, others: []) } }
        return WindowGrouping.group(windows, by: \.appKey).map { group in
            let primaryIndex = group.firstIndex { !$0.isDimmed } ?? 0
            var others = group
            let primary = others.remove(at: primaryIndex)
            return SwitcherItem(primary: primary, others: others)
        }
    }
}
