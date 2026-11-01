/// Arrow-key movement over the switcher's tiles, laid out row by row.
enum GridNavigation {
    enum Direction {
        case left, right, up, down
    }

    /// ←/→ walk the tiles in order and wrap around. ↑/↓ change row in the same column, wrapping
    /// between the first and last row; a column missing from a shorter last row lands on its last tile.
    static func move(from index: Int, _ direction: Direction, count: Int, columns: Int) -> Int {
        guard count > 0 else { return 0 }
        let columns = max(1, min(columns, count))
        let rows = (count + columns - 1) / columns
        let (row, column) = (index / columns, index % columns)

        switch direction {
        case .left:
            return (index - 1 + count) % count
        case .right:
            return (index + 1) % count
        case .up, .down:
            guard rows > 1 else { return index }
            let step = direction == .down ? 1 : rows - 1
            let target = ((row + step) % rows) * columns + column
            return min(target, count - 1)
        }
    }
}
