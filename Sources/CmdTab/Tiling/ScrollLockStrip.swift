import Foundation

/// The windows of one desktop as Scroll Lock arranges them: columns left to right, each holding
/// one window or a stack of up to three. Pure state, so every rearrangement can be tested.
struct ScrollLockStrip<Window: Hashable>: Equatable {
    struct Column: Equatable {
        var windows: [Window]
        var width: ColumnWidth
        /// Explicit heights; windows without one share what's left equally.
        var heights: [Window: StackHeight] = [:]
    }

    static var maximumStack: Int { 3 }

    private(set) var columns: [Column] = []
    /// The focused window, if it is on the strip.
    private(set) var focused: Window?

    var windows: [Window] { columns.flatMap(\.windows) }
    var isEmpty: Bool { columns.isEmpty }

    var focusedColumnIndex: Int? {
        guard let focused else { return nil }
        return columnIndex(of: focused)
    }

    func columnIndex(of window: Window) -> Int? {
        columns.firstIndex { $0.windows.contains(window) }
    }

    func contains(_ window: Window) -> Bool { columnIndex(of: window) != nil }

    // MARK: - Membership

    /// Adds a window in its own column, right after the focused column (or at the end).
    mutating func insert(_ window: Window, width: ColumnWidth) {
        guard !contains(window) else { return }
        let index = focusedColumnIndex.map { $0 + 1 } ?? columns.count
        columns.insert(Column(windows: [window], width: width), at: index)
    }

    /// Adds a window at the end, keeping the order windows had on screen when Scroll Lock starts.
    mutating func append(_ window: Window, width: ColumnWidth) {
        guard !contains(window) else { return }
        columns.append(Column(windows: [window], width: width))
    }

    mutating func remove(_ window: Window) {
        guard let index = columnIndex(of: window) else { return }
        let wasFocused = focused == window
        columns[index].windows.removeAll { $0 == window }
        columns[index].heights[window] = nil
        if columns[index].windows.isEmpty {
            columns.remove(at: index)
        }
        if wasFocused {
            // Focus the neighbour that took its place, like closing a tab.
            focused = columns.isEmpty ? nil : columns[min(index, columns.count - 1)].windows.first
        }
    }

    /// Keeps only `windows`, in their current places.
    mutating func retain(_ windows: Set<Window>) {
        for window in self.windows where !windows.contains(window) {
            remove(window)
        }
    }

    mutating func focus(_ window: Window) {
        guard contains(window) else { return }
        focused = window
    }

    // MARK: - Moving focus

    /// Focuses the column `offset` columns away, landing on its first window. Stops at the ends,
    /// or with `wrapping` goes round from the last column to the first and back.
    @discardableResult
    mutating func focusColumn(by offset: Int, wrapping: Bool = false) -> Window? {
        guard let index = focusedColumnIndex else {
            focused = columns.first?.windows.first
            return focused
        }
        let count = columns.count
        let target = wrapping ? ((index + offset) % count + count) % count : min(max(index + offset, 0), count - 1)
        if target != index {
            focused = columns[target].windows.first
        }
        return focused
    }

    /// Moves focus up or down inside the focused stack.
    @discardableResult
    mutating func focusInStack(by offset: Int) -> Window? {
        guard let focused, let index = columnIndex(of: focused),
              let row = columns[index].windows.firstIndex(of: focused)
        else { return self.focused }
        let windows = columns[index].windows
        self.focused = windows[min(max(row + offset, 0), windows.count - 1)]
        return self.focused
    }

    // MARK: - Rearranging

    /// Swaps the focused column with its neighbour.
    mutating func moveFocusedColumn(by offset: Int) {
        guard let index = focusedColumnIndex else { return }
        let target = index + offset
        guard columns.indices.contains(target) else { return }
        columns.swapAt(index, target)
    }

    /// Sends the focused column to the first or last place.
    mutating func moveFocusedColumnToEnd(_ toEnd: Bool) {
        guard let index = focusedColumnIndex else { return }
        moveColumn(from: index, to: toEnd ? columns.count - 1 : 0)
    }

    /// Takes the column at `from` out and puts it at `to` (positions after the move). Used when a tile
    /// is dragged in the Arrange mode bar.
    mutating func moveColumn(from: Int, to: Int) {
        guard columns.indices.contains(from) else { return }
        let column = columns.remove(at: from)
        columns.insert(column, at: min(max(to, 0), columns.count))
    }

    /// Drag to a column's edge: the window gets its own column right before or after the column holding
    /// `target`, leaving its stack if it was in one.
    mutating func move(_ window: Window, besideColumnOf target: Window, after: Bool) {
        guard window != target, let source = columnIndex(of: window), columnIndex(of: target) != nil else { return }
        let width = columns[source].width
        let isAlone = columns[source].windows.count == 1
        if isAlone {
            let column = columns.remove(at: source)
            guard let targetIndex = columnIndex(of: target) else { columns.insert(column, at: source); return }
            columns.insert(column, at: after ? targetIndex + 1 : targetIndex)
        } else {
            detach(window)
            guard let targetIndex = columnIndex(of: target) else { return }
            columns.insert(Column(windows: [window], width: width), at: after ? targetIndex + 1 : targetIndex)
        }
    }

    /// Arrange mode's S then ← or →: the window joins the column on that side, at the bottom, splitting
    /// the height. Returns whether it moved.
    @discardableResult
    mutating func stackIntoNeighbour(_ window: Window, toTheRight: Bool) -> Bool {
        guard let index = columnIndex(of: window) else { return false }
        let target = index + (toTheRight ? 1 : -1)
        guard columns.indices.contains(target), let bottom = columns[target].windows.last,
              canStack(window, onto: bottom)
        else { return false }
        stack(window, onto: bottom, below: true, height: .half)
        return true
    }

    /// Arrange mode's bar: a tile dropped onto another. The dropped column's first window joins the
    /// target column at the bottom, splitting the height. Returns whether it moved.
    @discardableResult
    mutating func stackColumn(_ from: Int, into target: Int) -> Bool {
        guard from != target, columns.indices.contains(from), columns.indices.contains(target),
              let window = columns[from].windows.first, let bottom = columns[target].windows.last,
              canStack(window, onto: bottom)
        else { return false }
        stack(window, onto: bottom, below: true, height: .half)
        return true
    }

    /// Focuses the column at a position (Arrange mode's 1–9).
    @discardableResult
    mutating func focusColumn(at index: Int) -> Window? {
        guard columns.indices.contains(index) else { return focused }
        focused = columns[index].windows.first
        return focused
    }

    mutating func setWidth(_ width: ColumnWidth, ofColumnWith window: Window) {
        guard let index = columnIndex(of: window) else { return }
        columns[index].width = width
    }

    /// Sets a stacked window's height. `full` takes it out of the stack into its own column.
    mutating func setHeight(_ height: StackHeight, of window: Window) {
        guard let index = columnIndex(of: window) else { return }
        if height == .full {
            unstack(window)
        } else if columns[index].windows.count > 1 {
            // The others share what's left, so 33% really leaves 67% to the rest.
            columns[index].heights = [window: height]
        }
    }

    /// ⌃⌥⇧R: switches a stacked window between a third and half of the column. (Taking it out of the
    /// stack is ⌃⌥S, so cycling never unstacks by surprise.)
    mutating func cycleHeight(of window: Window) -> StackHeight? {
        guard let index = columnIndex(of: window), columns[index].windows.count > 1 else { return nil }
        let fractions = heightFractions(of: columns[index])
        guard let row = columns[index].windows.firstIndex(of: window) else { return nil }
        let next: StackHeight = fractions[row] > 0.4 ? .third : .half
        setHeight(next, of: window)
        return next
    }

    /// ⌃⌥S: a stacked window leaves its stack; a lone window joins the column on its left.
    mutating func toggleStack(_ window: Window, height: StackHeight) {
        guard let index = columnIndex(of: window) else { return }
        if columns[index].windows.count > 1 {
            unstack(window)
        } else if index > 0 {
            guard columns[index - 1].windows.count < Self.maximumStack else { return }
            detach(window) // Removes column `index`, so the one on its left keeps its index.
            insert(window, intoColumn: index - 1, at: columns[index - 1].windows.count, height: height)
        }
    }

    /// Puts `window` into the column holding `target`, just above or below it. Used by drag and drop.
    mutating func stack(_ window: Window, onto target: Window, below: Bool, height: StackHeight) {
        guard window != target, let targetIndex = columnIndex(of: target) else { return }
        guard let row = columns[targetIndex].windows.firstIndex(of: target) else { return }
        let sameColumn = columns[targetIndex].windows.contains(window)
        guard sameColumn || columns[targetIndex].windows.count < Self.maximumStack else { return }

        var position = below ? row + 1 : row
        if sameColumn, let current = columns[targetIndex].windows.firstIndex(of: window), current < position {
            position -= 1
        }
        detach(window)
        guard let newTargetIndex = columnIndex(of: target) else { return }
        insert(window, intoColumn: newTargetIndex, at: position, height: height)
    }

    /// Whether `window` can join the column holding `target`.
    func canStack(_ window: Window, onto target: Window) -> Bool {
        guard window != target, let index = columnIndex(of: target) else { return false }
        let column = columns[index]
        return column.windows.contains(window) || column.windows.count < Self.maximumStack
    }

    /// Takes a stacked window into its own column, right after the stack.
    mutating func unstack(_ window: Window) {
        guard let index = columnIndex(of: window), columns[index].windows.count > 1 else { return }
        let width = columns[index].width
        detach(window)
        columns.insert(Column(windows: [window], width: width), at: index + 1)
    }

    /// Heights of a column's windows as shares of the column, top to bottom.
    /// A window on its own fills the column unless it was given a height (then the rest stays empty).
    /// In a stack, windows without a height share what the others leave; when that leaves too little,
    /// or the heights add up to more than the column, they are evened out or scaled to fit.
    func heightFractions(of column: Column) -> [Double] {
        let count = column.windows.count
        guard count > 1 else { return [column.windows.first.flatMap { column.heights[$0]?.fraction } ?? 1] }
        let explicit = column.windows.map { column.heights[$0]?.fraction }
        let taken = explicit.compactMap { $0 }.reduce(0, +)
        let freeCount = explicit.filter { $0 == nil }.count
        if freeCount > 0 {
            let share = (1 - taken) / Double(freeCount)
            guard share >= 0.15 else { return Array(repeating: 1 / Double(count), count: count) }
            return explicit.map { $0 ?? share }
        }
        return taken > 1 ? explicit.map { ($0 ?? 0) / taken } : explicit.map { $0 ?? 0 }
    }

    /// ⇧↑ ⇧↓ in Arrange mode: the arrow moves the window's edge that can move, like dragging the divider.
    /// The bottom window of a stack moves its top edge (up = taller); any other window, or one on its
    /// own, moves its bottom edge (up = shorter).
    @discardableResult
    mutating func moveHeightEdge(of window: Window, up: Bool) -> StackHeight? {
        guard let index = columnIndex(of: window) else { return nil }
        let windows = columns[index].windows
        let isBottomOfStack = windows.count > 1 && windows.last == window
        return stepHeight(of: window, taller: isBottomOfStack ? up : !up)
    }

    /// ⇧↑ ⇧↓ in Arrange mode: one preset taller or shorter, as a share of the whole column. A window on
    /// its own stays at the top with the rest of the column empty; in a stack the others share the
    /// rest (each keeps at least a quarter). Returns the new height, or `nil` at the limit.
    @discardableResult
    mutating func stepHeight(of window: Window, taller: Bool) -> StackHeight? {
        guard let index = columnIndex(of: window), let row = columns[index].windows.firstIndex(of: window) else { return nil }
        let count = columns[index].windows.count
        let current = heightFractions(of: columns[index])[row]
        let limit = 1 - 0.25 * Double(count - 1) + 0.001
        let presets = StackHeight.allCases.filter { $0.fraction <= limit }
        let next = taller
            ? presets.first { $0.fraction > current + 0.01 }
            : presets.last { $0.fraction < current - 0.01 }
        guard let next else { return nil }
        columns[index].heights = next == .full ? [:] : [window: next]
        return next
    }

    // MARK: - Helpers

    private mutating func detach(_ window: Window) {
        guard let index = columnIndex(of: window) else { return }
        columns[index].windows.removeAll { $0 == window }
        columns[index].heights[window] = nil
        if columns[index].windows.isEmpty {
            columns.remove(at: index)
        } else if columns[index].windows.count == 1 {
            columns[index].heights = [:]
        }
    }

    /// Inserts a window that is on no column into an existing one.
    private mutating func insert(_ window: Window, intoColumn index: Int, at row: Int, height: StackHeight) {
        guard columns.indices.contains(index), columns[index].windows.count < Self.maximumStack else { return }
        columns[index].windows.insert(window, at: min(row, columns[index].windows.count))
        if height != .full {
            columns[index].heights[window] = height
        }
    }
}
