import CoreGraphics

/// What the switcher should list.
struct WindowFilterOptions: Equatable {
    var scope: SpaceScope
    var includesMinimized: Bool
    var includesHiddenApps: Bool
    /// Apps set to "Hide" in Exceptions.
    var excludedBundleIDs: Set<String> = []
}

/// Pure selection/ordering rules, kept free of system calls so they are unit-testable.
enum WindowOrdering {
    /// Normal application windows live on layer 0; menus, the Dock, overlays etc. live above.
    static let normalWindowLayer = 0
    /// Apps keep tiny invisible windows around (drag helpers, status windows…).
    static let minimumWindowSide: CGFloat = 50

    /// Keeps plausible app windows owned by `eligiblePIDs`, preserving the WindowServer's
    /// front-to-back order — which doubles as a free "most recently used" order.
    static func candidates(
        from entries: [WindowServerEntry],
        eligiblePIDs: Set<pid_t>
    ) -> [WindowServerEntry] {
        entries.filter { entry in
            entry.layer == normalWindowLayer
                && eligiblePIDs.contains(entry.pid)
                && entry.size.width >= minimumWindowSide
                && entry.size.height >= minimumWindowSide
        }
    }

    /// Whether a window should be listed for the requested scope.
    static func isVisible(windowSpaces: Set<UInt64>, currentSpaces: Set<UInt64>, scope: SpaceScope) -> Bool {
        guard !windowSpaces.isEmpty else { return false } // Not on any Space: helper/offscreen window.
        switch scope {
        case .allSpaces:
            return true
        case .currentSpace:
            // If Space info is unavailable, show everything rather than nothing.
            return currentSpaces.isEmpty || !windowSpaces.isDisjoint(with: currentSpaces)
        }
    }

    /// Most recently used first. Only the on-screen list is in true front-to-back order (the full list
    /// puts ordered-out windows on top), so visible windows rank by it and every other window follows
    /// in full-list order.
    static func zIndex(onScreenOrder: [CGWindowID], fullOrder: [CGWindowID]) -> [CGWindowID: Int] {
        var index: [CGWindowID: Int] = [:]
        for id in onScreenOrder where index[id] == nil {
            index[id] = index.count
        }
        for id in fullOrder where index[id] == nil {
            index[id] = index.count
        }
        return index
    }

    /// A window on the current desktop that is neither visible, minimized nor hidden with its app has
    /// been ordered out (a closed document kept alive, a dismissed panel): not something to switch to.
    static func isOrderedOut(isOnScreen: Bool, isOnCurrentSpace: Bool, isMinimized: Bool, isAppHidden: Bool) -> Bool {
        isOnCurrentSpace && !isOnScreen && !isMinimized && !isAppHidden
    }

    /// Whether a window passes the minimized / hidden-app filters.
    static func isIncluded(isMinimized: Bool, isAppHidden: Bool, options: WindowFilterOptions) -> Bool {
        (options.includesMinimized || !isMinimized) && (options.includesHiddenApps || !isAppHidden)
    }

    /// Front-to-back order, with minimized/hidden windows moved after the visible ones.
    static func arranged<Item>(
        _ items: [Item],
        zIndex: (Item) -> Int,
        isDimmed: (Item) -> Bool
    ) -> [Item] {
        items.sorted { lhs, rhs in
            let (lhsDimmed, rhsDimmed) = (isDimmed(lhs), isDimmed(rhs))
            if lhsDimmed != rhsDimmed { return !lhsDimmed }
            return zIndex(lhs) < zIndex(rhs)
        }
    }
}
