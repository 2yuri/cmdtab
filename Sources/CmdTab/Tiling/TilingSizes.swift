import Foundation

/// How wide a Scroll Lock column is, as a share of the usable screen width.
enum ColumnWidth: String, Codable, CaseIterable, Sendable {
    case third, half, twoThirds, full

    var fraction: Double {
        switch self {
        case .third: 1.0 / 3
        case .half: 0.5
        case .twoThirds: 2.0 / 3
        case .full: 1
        }
    }

    var label: String {
        switch self {
        case .third: "33%"
        case .half: "50%"
        case .twoThirds: "66%"
        case .full: "100%"
        }
    }

    /// Equal parts the screen is split into for the settings glyph, and how many the column takes.
    var glyphCells: (total: Int, filled: Int) {
        switch self {
        case .third: (3, 1)
        case .half: (2, 1)
        case .twoThirds: (3, 2)
        case .full: (1, 1)
        }
    }

    /// The next width for ⌃⌥R, wrapping around.
    var next: ColumnWidth {
        let all = Self.allCases
        return all[(all.firstIndex(of: self)! + 1) % all.count]
    }

    /// One step wider or narrower (Arrange mode's ↑ ↓), stopping at 33% and 100%.
    func step(_ wider: Bool) -> ColumnWidth {
        let all = Self.allCases
        let index = all.firstIndex(of: self)! + (wider ? 1 : -1)
        return all[min(max(index, 0), all.count - 1)]
    }

    /// The preset closest to a width the user dragged a window to.
    static func nearest(to fraction: Double) -> ColumnWidth {
        allCases.min { abs($0.fraction - fraction) < abs($1.fraction - fraction) }!
    }
}

/// How tall a window is inside a column it shares with others.
enum StackHeight: String, Codable, CaseIterable, Sendable {
    case quarter, third, half, twoThirds, threeQuarters, full

    var fraction: Double {
        switch self {
        case .quarter: 0.25
        case .third: 1.0 / 3
        case .half: 0.5
        case .twoThirds: 2.0 / 3
        case .threeQuarters: 0.75
        case .full: 1
        }
    }

    var label: String {
        switch self {
        case .quarter: "25%"
        case .third: "33%"
        case .half: "50%"
        case .twoThirds: "66%"
        case .threeQuarters: "75%"
        case .full: "100%"
        }
    }

    var glyphCells: (total: Int, filled: Int) {
        switch self {
        case .quarter: (4, 1)
        case .third: (3, 1)
        case .half: (2, 1)
        case .twoThirds: (3, 2)
        case .threeQuarters: (4, 3)
        case .full: (1, 1)
        }
    }

    /// The choices offered in Settings for a window joining a stack.
    static let settingsChoices: [StackHeight] = [.third, .half, .full]

    /// The next height for ⌃⌥⇧R. `full` takes the window out of the stack.
    var next: StackHeight {
        let all = Self.settingsChoices
        return all[((all.firstIndex(of: self) ?? 0) + 1) % all.count]
    }

    /// The share closest to a height the user dragged a stacked window to. Never `full`:
    /// dragging inside a stack keeps the window in it.
    static func nearest(to fraction: Double) -> StackHeight {
        allCases.filter { $0 != .full }.min { abs($0.fraction - fraction) < abs($1.fraction - fraction) }!
    }
}

/// When the strip scrolls to put the focused column in the middle of the screen.
enum CentreMode: String, Codable, CaseIterable, Sendable {
    case never, whenOverflowing, always

    var label: String {
        switch self {
        case .never: "Never"
        case .whenOverflowing: "When it overflows"
        case .always: "Always"
        }
    }
}

/// A size the user gave an app's windows, reused for its next windows.
struct RememberedSize: Codable, Hashable, Identifiable, Sendable {
    var bundleID: String
    var name: String
    var width: ColumnWidth?
    var height: StackHeight?

    var id: String { bundleID }
}

/// An app whose windows Scroll Lock leaves alone (Settings → Tiling › Floating Apps).
struct FloatingApp: Codable, Hashable, Identifiable, Sendable {
    var bundleID: String
    var name: String

    var id: String { bundleID }
}

/// Which apps float instead of tiling.
enum FloatingRule {
    /// Browsers that ship with macOS still tile: they're where people spend their day.
    static let systemAppsThatTile: Set<String> = ["com.apple.Safari"]

    /// Apps that come with macOS live under /System (Finder in CoreServices, the rest in Applications).
    static func isSystemApp(bundlePath: String?, bundleID: String?) -> Bool {
        guard let bundlePath, bundlePath.hasPrefix("/System/") else { return false }
        return !systemAppsThatTile.contains(bundleID ?? "")
    }

    static func floats(
        bundleID: String?,
        bundlePath: String?,
        floatsSystemApps: Bool,
        floatingApps: Set<String>
    ) -> Bool {
        if let bundleID, floatingApps.contains(bundleID) { return true }
        return floatsSystemApps && isSystemApp(bundlePath: bundlePath, bundleID: bundleID)
    }
}

/// When dropping a window on another column stacks them.
enum DragToStack: String, Codable, CaseIterable, Sendable {
    case always, inArrangeMode, off

    var label: String {
        switch self {
        case .always: "Always"
        case .inArrangeMode: "In Arrange mode"
        case .off: "Off"
        }
    }
}
