import Foundation

/// The windows of one desktop as Scroll Lock arranges them: columns left to right, each holding
/// one window, a stack of up to three sharing the height, or tabs: any number taking turns at full
/// height. Pure state, so every rearrangement can be tested.
struct ScrollLockStrip<Window: Hashable>: Equatable {
    struct Column: Equatable {
        var windows: [Window]
        var width: ColumnWidth
        /// Explicit heights; windows without one share what's left equally.
        var heights: [Window: StackHeight] = [:]
        /// Tabs: the windows take turns at full height, `active` in front. A column is split or
        /// tabbed, never both; with one window left it is a plain column again.
        var isTabbed = false
        var active: Window?

        /// The window you land on: the front tab, or the top of a stack.
        var entry: Window? { isTabbed ? (active ?? windows.first) : windows.first }
        /// Holds more than one window sharing the height.
        var isSplit: Bool { !isTabbed && windows.count > 1 }
    }

    static var maximumStack: Int { 3 }

    private(set) var columns: [Column] = []
    /// The focused window, if it is on the strip.
    private(set) var focused: Window?
    /// Windows focused before, most recent last: closing a window goes back to the one before it.
    private(set) var history: [Window] = []

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

    /// Puts `new` exactly where `old` was (same column, same width and height), for an app that
    /// swaps one window for another (a launcher that becomes a document window and back).
    mutating func replace(_ old: Window, with new: Window) {
        guard !contains(new), let column = columnIndex(of: old),
              let row = columns[column].windows.firstIndex(of: old) else { return }
        columns[column].windows[row] = new
        if let height = columns[column].heights.removeValue(forKey: old) {
            columns[column].heights[new] = height
        }
        if columns[column].active == old { columns[column].active = new }
        history = history.map { $0 == old ? new : $0 }
        if focused == old { focused = new }
    }

    mutating func remove(_ window: Window) {
        guard let index = columnIndex(of: window) else { return }
        let wasFocused = focused == window
        history.removeAll { $0 == window }
        detach(window)
        if wasFocused {
            // Back to the window you were on before this one (open a window from column 5, close it,
            // you're on 5 again); with no history, the neighbour that took its place.
            focused = history.popLast() ?? (columns.isEmpty ? nil : columns[min(index, columns.count - 1)].entry)
            if let focused, let column = columnIndex(of: focused), columns[column].isTabbed {
                columns[column].active = focused
            }
        }
    }

    /// Keeps only `windows`, in their current places.
    mutating func retain(_ windows: Set<Window>) {
        for window in self.windows where !windows.contains(window) {
            remove(window)
        }
    }

    private mutating func setFocused(_ window: Window?) {
        if let window { focus(window) } else { focused = nil }
    }

    mutating func focus(_ window: Window) {
        guard contains(window) else { return }
        if let focused, focused != window {
            history.removeAll { $0 == focused }
            history.append(focused)
            if history.count > 20 { history.removeFirst() }
        }
        history.removeAll { $0 == window }
        focused = window
        if let index = columnIndex(of: window), columns[index].isTabbed { columns[index].active = window }
    }

    // MARK: - Moving focus

    /// Focuses the column `offset` columns away, landing on its first window. Stops at the ends,
    /// or with `wrapping` goes round from the last column to the first and back.
    @discardableResult
    mutating func focusColumn(by offset: Int, wrapping: Bool = false) -> Window? {
        guard let index = focusedColumnIndex else {
            setFocused(columns.first?.entry)
            return focused
        }
        let count = columns.count
        let target = wrapping ? ((index + offset) % count + count) % count : min(max(index + offset, 0), count - 1)
        if target != index {
            setFocused(columns[target].entry)
        }
        return focused
    }

    /// Moves focus up or down inside the focused stack, or to the previous or next tab (going round).
    @discardableResult
    mutating func focusInStack(by offset: Int) -> Window? {
        guard let focused, let index = columnIndex(of: focused),
              let row = columns[index].windows.firstIndex(of: focused)
        else { return self.focused }
        let windows = columns[index].windows
        if columns[index].isTabbed {
            setFocused(windows[((row + offset) % windows.count + windows.count) % windows.count])
        } else {
            setFocused(windows[min(max(row + offset, 0), windows.count - 1)])
        }
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
              let window = columns[from].entry, let bottom = columns[target].windows.last,
              canStack(window, onto: bottom)
        else { return false }
        stack(window, onto: bottom, below: true, height: .half)
        return true
    }

    /// Focuses the column at a position (Arrange mode's 1–9).
    @discardableResult
    mutating func focusColumn(at index: Int) -> Window? {
        guard columns.indices.contains(index) else { return focused }
        setFocused(columns[index].entry)
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
        } else if columns[index].isSplit {
            // The others share what's left, so 33% really leaves 67% to the rest.
            columns[index].heights = [window: height]
        }
    }

    /// ⌃⌥⇧R: switches a stacked window between a third and half of the column. (Taking it out of the
    /// stack is ⌃⌥S, so cycling never unstacks by surprise.)
    mutating func cycleHeight(of window: Window) -> StackHeight? {
        guard let index = columnIndex(of: window), columns[index].isSplit else { return nil }
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
            guard !columns[index - 1].isTabbed, columns[index - 1].windows.count < Self.maximumStack else { return }
            detach(window) // Removes column `index`, so the one on its left keeps its index.
            insert(window, intoColumn: index - 1, at: columns[index - 1].windows.count, height: height)
        }
    }

    /// Puts `window` into the column holding `target`, just above or below it. Used by drag and drop.
    mutating func stack(_ window: Window, onto target: Window, below: Bool, height: StackHeight) {
        guard window != target, let targetIndex = columnIndex(of: target) else { return }
        guard let row = columns[targetIndex].windows.firstIndex(of: target) else { return }
        let sameColumn = columns[targetIndex].windows.contains(window)
        guard !columns[targetIndex].isTabbed, sameColumn || columns[targetIndex].windows.count < Self.maximumStack else { return }

        var position = below ? row + 1 : row
        if sameColumn, let current = columns[targetIndex].windows.firstIndex(of: window), current < position {
            position -= 1
        }
        detach(window)
        guard let newTargetIndex = columnIndex(of: target) else { return }
        insert(window, intoColumn: newTargetIndex, at: position, height: height)
    }

    /// The strip as the island's column bar shows it while `window` is dragged: without that window.
    func without(_ window: Window) -> ScrollLockStrip {
        var copy = self
        copy.detach(window)
        return copy
    }

    /// The island's column bar: `window` gets its own column at `gap` of the strip without it
    /// (0 is before the first column), leaving its stack if it was in one.
    mutating func place(_ window: Window, inGap gap: Int) {
        guard let source = columnIndex(of: window) else { return }
        let width = columns[source].width
        detach(window)
        columns.insert(Column(windows: [window], width: width), at: min(max(gap, 0), columns.count))
    }

    /// The island's column bar: `window` joins column `index` of the strip without it, at the
    /// bottom, splitting the height. Returns whether it moved (a column holds three at most).
    @discardableResult
    mutating func place(_ window: Window, intoColumn index: Int) -> Bool {
        var rest = without(window)
        guard rest.columns.indices.contains(index), contains(window) else { return false }
        if rest.columns[index].isTabbed {
            rest.addTab(window, toColumn: index)
            columns = rest.columns
            return true
        }
        guard rest.columns[index].windows.count < Self.maximumStack else { return false }
        rest.insert(window, intoColumn: index, at: rest.columns[index].windows.count, height: .half)
        columns = rest.columns
        return true
    }

    /// Whether `window` can join the column holding `target`.
    func canStack(_ window: Window, onto target: Window) -> Bool {
        guard window != target, let index = columnIndex(of: target) else { return false }
        let column = columns[index]
        guard !column.isTabbed else { return false }
        return column.windows.contains(window) || column.windows.count < Self.maximumStack
    }

    // MARK: - Tabs

    /// Whether `window` can become a tab in the column holding `target`: a column on its own or
    /// already tabbed, never a split stack.
    func canTab(_ window: Window, onto target: Window) -> Bool {
        guard window != target, let index = columnIndex(of: target) else { return false }
        return !columns[index].isSplit && !columns[index].windows.contains(window)
    }

    /// Drop on a column's title bar: `window` becomes a tab of the column holding `target`, in front.
    @discardableResult
    mutating func tab(_ window: Window, onto target: Window) -> Bool {
        guard canTab(window, onto: target), contains(window) else { return false }
        detach(window)
        guard let index = columnIndex(of: target) else { return false }
        addTab(window, toColumn: index)
        return true
    }

    /// ⌃⌥T: a window on its own becomes a tab of the column on its left; a tab leaves for its own
    /// column, right after. Returns whether anything changed (not for a window in a split stack, or
    /// with no column on its left that can take tabs).
    @discardableResult
    mutating func toggleTab(_ window: Window) -> Bool {
        guard let index = columnIndex(of: window) else { return false }
        if columns[index].isTabbed {
            let width = columns[index].width
            detach(window)
            columns.insert(Column(windows: [window], width: width), at: index + 1)
            return true
        }
        guard columns[index].windows.count == 1, index > 0, !columns[index - 1].isSplit else { return false }
        detach(window) // Removes column `index`, so the one on its left keeps its index.
        addTab(window, toColumn: index - 1)
        return true
    }

    /// Arrange mode's T then ← or →: the window becomes a tab of the column on that side.
    @discardableResult
    mutating func tabIntoNeighbour(_ window: Window, toTheRight: Bool) -> Bool {
        guard let index = columnIndex(of: window) else { return false }
        let target = index + (toTheRight ? 1 : -1)
        guard columns.indices.contains(target), let entry = columns[target].entry else { return false }
        return tab(window, onto: entry)
    }

    /// Tabs front to back: the one in front, then the others by when you last used them, so the
    /// window you were just on sits right behind (where macOS keeps it, too).
    func tabOrder(of column: Column) -> [Window] {
        guard column.isTabbed, let front = column.entry else { return column.windows }
        let recency = Dictionary(history.enumerated().map { ($1, $0) }, uniquingKeysWith: max)
        let rest = column.windows.filter { $0 != front }.sorted { (recency[$0] ?? -1) > (recency[$1] ?? -1) }
        return [front] + rest
    }

    private mutating func addTab(_ window: Window, toColumn index: Int) {
        columns[index].windows.append(window)
        columns[index].isTabbed = true
        columns[index].heights = [:]
        columns[index].active = window
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
        if column.isTabbed { return Array(repeating: 1, count: count) } // Every tab is full height.
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
        guard let index = columnIndex(of: window), !columns[index].isTabbed,
              let row = columns[index].windows.firstIndex(of: window) else { return nil }
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
        guard let index = columnIndex(of: window), let row = columns[index].windows.firstIndex(of: window) else { return }
        columns[index].windows.remove(at: row)
        columns[index].heights[window] = nil
        if columns[index].windows.isEmpty {
            columns.remove(at: index)
        } else if columns[index].windows.count == 1 {
            columns[index].heights = [:]
            columns[index].isTabbed = false
            columns[index].active = nil
        } else if columns[index].active == window {
            // The tab you used before comes to the front, or the one that took its place.
            let windows = columns[index].windows
            columns[index].active = history.last { windows.contains($0) } ?? windows[min(row, windows.count - 1)]
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
