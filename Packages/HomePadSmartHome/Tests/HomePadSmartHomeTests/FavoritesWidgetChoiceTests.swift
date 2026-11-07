import Foundation
import HomePadCore
import Testing
@testable import HomePadSmartHome

/// Which accessories one Home Favorites widget shows, and how Edit Widget changes them.
@Suite struct FavoritesWidgetChoiceTests {
    static func accessory(_ id: String, _ kind: AccessoryKind = .light) -> HomeAccessory {
        HomeAccessory(id: id, name: id, kind: kind, backend: .demo)
    }

    let home = ["lock", "kitchen", "porch", "coffee"].map { accessory($0) }
    var favorites: [HomeAccessory] { [home[0], home[1]] }

    /// Nothing chosen shows the Home app's favorites, exactly as the widget always did.
    @Test func byDefaultTheWidgetShowsTheFavorites() {
        #expect(WidgetSettings()[FavoritesWidgetChoice.accessories] == nil)
        let shown = FavoritesWidgetChoice.shown(nil, favorites: favorites, accessories: home)
        #expect(shown.map(\.id) == ["lock", "kitchen"])
    }

    /// Chosen accessories show in their order, and one gone from the home drops off.
    @Test func chosenAccessoriesShowInTheirOrder() {
        let shown = FavoritesWidgetChoice.shown(["coffee", "gone", "lock"], favorites: favorites, accessories: home)
        #expect(shown.map(\.id) == ["coffee", "lock"])
    }

    /// The first change keeps the favorites the widget showed and changes only that one.
    @Test func theFirstChangeStartsFromTheFavorites() {
        let shown = favorites.map(\.id)
        #expect(FavoritesWidgetChoice.toggling("porch", shown: shown) == ["lock", "kitchen", "porch"])
        #expect(FavoritesWidgetChoice.toggling("lock", shown: shown) == ["kitchen"])
    }

    /// Taking off the last accessory goes back to following the favorites.
    @Test func anEmptyChoiceFollowsTheFavoritesAgain() {
        #expect(FavoritesWidgetChoice.toggling("lock", shown: ["lock"]) == nil)
        #expect(FavoritesWidgetChoice.removing(["lock"], at: IndexSet(integer: 0)) == nil)
    }

    @Test func movingAndRemovingKeepTheRest() {
        #expect(FavoritesWidgetChoice.moving(["a", "b", "c"], from: IndexSet(integer: 2), to: 0) == ["c", "a", "b"])
        #expect(FavoritesWidgetChoice.removing(["a", "b", "c"], at: IndexSet(integer: 1)) == ["a", "c"])
    }

    /// Two widgets keep two lists: the choice lives in each widget's own settings.
    @Test func eachWidgetKeepsItsOwnChoice() throws {
        var door = WidgetSettings()
        door[FavoritesWidgetChoice.accessories] = ["lock"]
        var kitchen = WidgetSettings()
        kitchen[FavoritesWidgetChoice.accessories] = ["kitchen", "coffee"]
        let decoded = try JSONDecoder().decode(WidgetSettings.self, from: JSONEncoder().encode(door))
        #expect(FavoritesWidgetChoice.shown(decoded[FavoritesWidgetChoice.accessories], favorites: favorites, accessories: home)
            .map(\.id) == ["lock"])
        #expect(FavoritesWidgetChoice.shown(kitchen[FavoritesWidgetChoice.accessories], favorites: favorites, accessories: home)
            .map(\.id) == ["kitchen", "coffee"])
    }
}
