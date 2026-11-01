/// A wrapping cursor over the switcher items.
struct SelectionCycle: Equatable {
    let count: Int
    private(set) var index = 0

    init(count: Int) {
        self.count = max(0, count)
    }

    mutating func moveForward() {
        guard count > 0 else { return }
        index = (index + 1) % count
    }

    mutating func moveBackward() {
        guard count > 0 else { return }
        index = (index - 1 + count) % count
    }

    mutating func select(_ newIndex: Int) {
        guard (0..<count).contains(newIndex) else { return }
        index = newIndex
    }
}
