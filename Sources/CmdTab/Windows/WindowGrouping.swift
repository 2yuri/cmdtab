/// Groups items by key, keeping both the order of the groups (first appearance) and the order inside
/// each group. With most-recently-used input, each app lands where its latest window was.
enum WindowGrouping {
    static func group<Item, Key: Hashable>(_ items: [Item], by key: (Item) -> Key) -> [[Item]] {
        var groups: [[Item]] = []
        var groupIndex: [Key: Int] = [:]
        for item in items {
            let itemKey = key(item)
            if let index = groupIndex[itemKey] {
                groups[index].append(item)
            } else {
                groupIndex[itemKey] = groups.count
                groups.append([item])
            }
        }
        return groups
    }
}
