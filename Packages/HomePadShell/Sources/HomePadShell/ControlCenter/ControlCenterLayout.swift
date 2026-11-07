/// Which Control Center tiles show, in what order. Built-in tiles and module
/// tiles (`registry.controls`) share one list. Like the Home Screen, tiles the
/// user removed stay known so they are not added back, while new module tiles are.
struct ControlCenterLayout: Codable, Equatable, Sendable {
    /// Visible tiles, in order.
    var tileIDs: [String]
    /// Every tile ID that has been offered at least once.
    var knownIDs: Set<String>

    static func makeDefault(availableIDs: [String]) -> ControlCenterLayout {
        ControlCenterLayout(tileIDs: availableIDs, knownIDs: Set(availableIDs))
    }

    /// The layout with newly available tiles appended.
    func reconciled(withAvailableIDs ids: [String]) -> ControlCenterLayout {
        let newIDs = ids.filter { !knownIDs.contains($0) }
        guard !newIDs.isEmpty else { return self }
        var copy = self
        copy.tileIDs.append(contentsOf: newIDs)
        copy.knownIDs.formUnion(newIDs)
        return copy
    }

    mutating func remove(_ id: String) {
        tileIDs.removeAll { $0 == id }
    }

    mutating func add(_ id: String) {
        guard !tileIDs.contains(id) else { return }
        tileIDs.append(id)
        knownIDs.insert(id)
    }

    /// Puts the visible tiles in `order` (the same tiles, rearranged), leaving
    /// tiles that are not showing, such as one from a module that is not
    /// loaded, where they were.
    mutating func reorder(visible order: [String]) {
        let visible = Set(order)
        var remaining = order[...]
        tileIDs = tileIDs.map { visible.contains($0) ? remaining.popFirst() ?? $0 : $0 }
    }
}
