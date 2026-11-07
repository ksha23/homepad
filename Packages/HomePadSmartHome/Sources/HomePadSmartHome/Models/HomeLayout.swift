import HomePadCore

/// How big an accessory tile is in the Home app, from Apple Home's small set:
/// a compact square or a wide tile that spans two columns.
enum TileSize: String, Codable, Hashable, Sendable, CaseIterable {
    case small
    case wide

    var columnSpan: Int { self == .wide ? 2 : 1 }

    var title: String {
        switch self {
        case .small: "Small"
        case .wide: "Wide"
        }
    }
}

/// The person's curated Home layout: room order, what is shown, and tile sizes.
/// Rooms and accessories can be hidden. An accessory can be pinned so it shows
/// even when its room is hidden.
struct HomeLayout: Codable, Hashable, Sendable {
    var roomOrder: [String] = []
    var hiddenRooms: Set<String> = []
    var hiddenIDs: Set<String> = []
    var pinnedIDs: Set<String> = []
    var tileSizes: [String: TileSize] = [:]

    /// Whether an accessory or camera with this ID and room should appear.
    func isVisible(id: String, room: String?) -> Bool {
        if pinnedIDs.contains(id) { return true }
        if hiddenIDs.contains(id) { return false }
        if let room, hiddenRooms.contains(room) { return false }
        return true
    }

    mutating func setRoom(_ room: String, visible: Bool) {
        if visible { hiddenRooms.remove(room) } else { hiddenRooms.insert(room) }
    }

    /// Shows or hides one item. Showing an item in a hidden room pins it.
    mutating func setItem(_ id: String, room: String?, visible: Bool) {
        if visible {
            hiddenIDs.remove(id)
            if let room, hiddenRooms.contains(room) { pinnedIDs.insert(id) }
        } else {
            pinnedIDs.remove(id)
            hiddenIDs.insert(id)
        }
    }

    /// Rooms in the person's order. Rooms they never ordered follow alphabetically.
    func ordered(_ rooms: [String]) -> [String] {
        let known = roomOrder.filter(rooms.contains)
        let rest = rooms.filter { !roomOrder.contains($0) }.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
        return known + rest
    }

    /// The layout with each saved ID as this HomePad knows it. Where two saved
    /// tile sizes name one accessory, as when two HomePads each set one, the
    /// size saved under this HomePad's own ID wins.
    func localized(by localID: (String) -> String) -> HomeLayout {
        var layout = self
        layout.hiddenIDs = Set(hiddenIDs.map(localID))
        layout.pinnedIDs = Set(pinnedIDs.map(localID))
        layout.tileSizes = [:]
        for id in tileSizes.keys.sorted() {
            let local = localID(id)
            if layout.tileSizes[local] == nil || id == local {
                layout.tileSizes[local] = tileSizes[id]
            }
        }
        return layout
    }

    func tileSize(for accessory: HomeAccessory) -> TileSize {
        if let size = tileSizes[accessory.id] { return size }
        switch accessory.kind {
        case .thermostat, .mediaPlayer, .securitySystem: return .wide
        default: return .small
        }
    }
}
