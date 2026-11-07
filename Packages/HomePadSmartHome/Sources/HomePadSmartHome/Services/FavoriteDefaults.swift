import Foundation
import HomePadCore
import Observation

/// Picks favorites for people who never chose any: climate, locks, then lights.
enum FavoriteDefaults {
    static let priority: [AccessoryKind] = [.thermostat, .lock, .light, .garageDoor, .cover, .fan, .switchOutlet, .mediaPlayer]

    static func accessoryIDs(from accessories: [HomeAccessory], limit: Int = 6) -> [HomeAccessory.ID] {
        // A group stands in for its members, as on the Home app's tiles.
        let ranked = accessories.hidingGroupMembers.filter { priority.contains($0.kind) }
            .sorted { (priority.firstIndex(of: $0.kind) ?? 99) < (priority.firstIndex(of: $1.kind) ?? 99) }
        return Array(ranked.prefix(limit).map(\.id))
    }
}
