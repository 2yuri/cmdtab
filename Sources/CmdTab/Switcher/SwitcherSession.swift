import CoreGraphics

/// What one opening of the switcher shows: the windows, how they are grouped, the search query and
/// the selection. Pure value type, so closing/minimizing/filtering is testable without a screen.
struct SwitcherSession {
    private(set) var windows: [SwitcherWindow]
    let groupedByApp: Bool
    private(set) var query = ""
    private(set) var items: [SwitcherItem]
    var selection: SelectionCycle

    init(windows: [SwitcherWindow], groupedByApp: Bool) {
        self.windows = windows
        self.groupedByApp = groupedByApp
        items = SwitcherItem.items(from: windows, groupedByApp: groupedByApp)
        selection = SelectionCycle(count: items.count)
    }

    var selectedItem: SwitcherItem? {
        items.indices.contains(selection.index) ? items[selection.index] : nil
    }

    /// Filters by `query` and selects the best (first) match.
    mutating func search(_ query: String) {
        self.query = query
        rebuild(selecting: 0)
    }

    /// After ⌘W: the window is gone; the selection stays in place (on the next tile).
    mutating func removeWindow(_ windowID: CGWindowID) {
        windows.removeAll { $0.windowID == windowID }
        rebuild(selecting: selection.index)
    }

    /// After ⌘Q: every window of the app is gone.
    mutating func removeApp(_ appKey: String) {
        windows.removeAll { $0.appKey == appKey }
        rebuild(selecting: selection.index)
    }

    /// After ⌘M: the window stays listed, dimmed, where it was.
    mutating func markMinimized(_ windowID: CGWindowID) {
        for index in windows.indices where windows[index].windowID == windowID {
            windows[index].isMinimized = true
        }
        rebuild(selecting: selection.index)
    }

    private mutating func rebuild(selecting index: Int) {
        items = SearchFilter.filter(SwitcherItem.items(from: windows, groupedByApp: groupedByApp), query: query)
        selection = SelectionCycle(count: items.count)
        selection.select(min(index, max(items.count - 1, 0)))
    }
}
