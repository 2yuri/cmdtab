import AppKit
import Observation

/// With Tiling on, a tiled window dragged up to the island: the island shows the other columns,
/// and letting go between two moves the window there, on one stacks it into that column.
@MainActor
@Observable
final class NotchDrop {
    nonisolated struct Column: Equatable {
        /// The apps of the column's windows, top to bottom (for tabs, the one in front).
        var apps: [pid_t]
        /// How many tabs the column holds, or 1. Tabs take any number; a split stack holds three.
        var tabs = 1
    }

    nonisolated enum Target: Equatable {
        /// Its own column at this gap (0 is before the first column).
        case gap(Int)
        /// Stacked into this column.
        case column(Int)
    }

    nonisolated struct State: Equatable {
        var columns: [Column]
        var dragged: pid_t
        var target: Target?
    }

    /// While a tiled window is held at the top of the screen.
    private(set) var state: State?

    /// Set by the island while its Windows module is on.
    @ObservationIgnored var isEnabled = false
    /// Where the island shows the columns (AppKit coordinates), set by the island.
    @ObservationIgnored var columnsRect: CGRect = .zero
    /// The grown island (AppKit coordinates), set by the island.
    @ObservationIgnored var islandRect: CGRect = .zero

    /// How close to the top of the screen the pointer must be.
    nonisolated static let reach: CGFloat = 40
    /// The space between two columns on the island.
    nonisolated static let spacing: CGFloat = 8

    /// Whether the pointer keeps the columns up: near the top of the screen, or, once they show,
    /// anywhere over the grown island (the columns sit below the top band).
    func holds(_ pointer: CGPoint, screen: CGRect) -> Bool {
        if pointer.y >= screen.maxY - Self.reach { return true }
        return state != nil && islandRect.insetBy(dx: -Self.margin, dy: -Self.margin).contains(pointer)
    }

    /// Slack around the grown island before the columns go away.
    nonisolated static let margin: CGFloat = 24

    func show(_ columns: [Column], dragged: pid_t, pointerX: CGFloat) {
        let target = Self.target(atX: pointerX - columnsRect.minX, width: columnsRect.width, columns: columns)
        let new = State(columns: columns, dragged: dragged, target: target)
        if new != state { state = new }
    }

    #if DEBUG
    func preview(_ state: State) {
        isEnabled = true
        self.state = state
    }
    #endif

    func end() {
        if state != nil { state = nil }
    }

    /// What letting go at `x` (from the left of the columns) does. The outer quarter of a column and
    /// the space around it are its gaps; the middle stacks into it, unless it's full.
    nonisolated static func target(atX x: CGFloat, width: CGFloat, columns: [Column]) -> Target? {
        let count = columns.count
        guard width > 0, x >= -spacing, x <= width + spacing else { return nil }
        guard count > 0 else { return .gap(0) }
        let tile = (width - spacing * CGFloat(count - 1)) / CGFloat(count)
        guard tile > 0 else { return nil }
        let step = tile + spacing
        let index = min(max(Int((x / step).rounded(.down)), 0), count - 1)
        let within = x - CGFloat(index) * step
        if within < tile * 0.25 { return .gap(index) }
        if within > tile * 0.75 { return .gap(index + 1) }
        let column = columns[index]
        return column.tabs > 1 || column.apps.count < ScrollLockStrip<CGWindowID>.maximumStack ? .column(index) : nil
    }
}
