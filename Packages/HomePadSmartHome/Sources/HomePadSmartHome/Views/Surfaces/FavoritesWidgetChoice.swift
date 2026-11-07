import HomePadCore
import SwiftUI

/// Which accessories one Home Favorites widget shows. Until someone picks its
/// own in Edit Widget it shows the Home app's favorites, as it always did.
/// Each widget keeps its own list (`WidgetSettings`), so a widget by the door
/// can hold the locks while another holds the lights.
enum FavoritesWidgetChoice {
    /// The accessories the widget shows, in order. Nil follows the Home app's favorites.
    static let accessories = WidgetSettingKey<[HomeAccessory.ID]?>("accessories", default: nil)

    /// What the widget shows: the chosen accessories still in the home, in
    /// their order, or the favorites while nothing is chosen.
    static func shown(_ chosen: [HomeAccessory.ID]?, favorites: [HomeAccessory],
                      accessories: [HomeAccessory]) -> [HomeAccessory] {
        guard let chosen else { return favorites }
        return chosen.compactMap { id in accessories.first { $0.id == id } }
    }

    /// The choice after adding an accessory to the widget or taking it off.
    /// `shown` is what the widget shows now, so the first change keeps the
    /// favorites it showed and changes only that one. Taking off the last one
    /// leaves nothing chosen, and the widget follows the favorites again.
    static func toggling(_ id: HomeAccessory.ID, shown: [HomeAccessory.ID]) -> [HomeAccessory.ID]? {
        var ids = shown
        if let index = ids.firstIndex(of: id) {
            ids.remove(at: index)
        } else {
            ids.append(id)
        }
        return ids.isEmpty ? nil : ids
    }

    /// The choice with the shown accessories in a new order.
    static func moving(_ shown: [HomeAccessory.ID], from source: IndexSet, to destination: Int) -> [HomeAccessory.ID]? {
        var ids = shown
        ids.move(fromOffsets: source, toOffset: destination)
        return ids.isEmpty ? nil : ids
    }

    /// The choice without the shown accessories at these places.
    static func removing(_ shown: [HomeAccessory.ID], at offsets: IndexSet) -> [HomeAccessory.ID]? {
        var ids = shown
        ids.remove(atOffsets: offsets)
        return ids.isEmpty ? nil : ids
    }
}
