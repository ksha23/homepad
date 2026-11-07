import Foundation
import HomePadCore

/// What the person saved: favorites, the layout and the doorbell. Saved IDs
/// can be another HomePad's HomeKit IDs, so every read turns them into this
/// HomePad's (`localID(for:)`). A change saves this HomePad's IDs for what it
/// can name and keeps the rest as saved, so nothing another HomePad picked is
/// lost here.
extension UnifiedSmartHomeService {
    func localID(for id: String) -> String {
        homeKitIDs.localID(for: id)
    }

    func camera(_ id: HomeCamera.ID) -> HomeCamera? {
        let id = localID(for: id)
        return allCameras.first { $0.id == id }
    }

    // MARK: Layout

    var layout: HomeLayout {
        get { settings[SmartHomeSettings.layout].localized(by: localID(for:)) }
        set {
            settings[SmartHomeSettings.layout] = newValue
            rebuild()
        }
    }

    /// Rooms that have something visible, accessories or cameras, in the person's order.
    var orderedRooms: [String] {
        layout.ordered(Array(Set(rooms + cameras.compactMap(\.room))))
    }

    // MARK: Favorites

    var favoriteAccessoryIDs: [HomeAccessory.ID] {
        guard let saved = settings[SmartHomeSettings.favoriteAccessoryIDs] else {
            return FavoriteDefaults.accessoryIDs(from: accessories)
        }
        return localIDs(for: saved)
    }

    /// Scenes the person picked for the Home app. None until they pick some,
    /// as in Apple Home, so the app opens on accessories, not a row of scenes.
    var favoriteSceneIDs: [HomeScene.ID] {
        localIDs(for: settings[SmartHomeSettings.favoriteSceneIDs] ?? [])
    }

    var favoriteScenes: [HomeScene] {
        favoriteSceneIDs.compactMap { id in scenes.first { $0.id == id } }
    }

    /// Favorite scenes first, then the rest, for the Scenes widget and Control
    /// Center tile, which offer scenes even before any is a favorite.
    var scenesFavoritesFirst: [HomeScene] {
        let favorites = favoriteScenes
        return favorites + scenes.filter { scene in !favorites.contains { $0.id == scene.id } }
    }

    func setFavorite(_ accessoryID: HomeAccessory.ID, isFavorite: Bool) {
        let id = localID(for: accessoryID)
        var ids = favoriteAccessoryIDs.filter { $0 != id }
        if isFavorite { ids.append(id) }
        settings[SmartHomeSettings.favoriteAccessoryIDs] = ids
    }

    func setFavoriteScene(_ sceneID: HomeScene.ID, isFavorite: Bool) {
        let id = localID(for: sceneID)
        var ids = favoriteSceneIDs.filter { $0 != id }
        if isFavorite { ids.append(id) }
        settings[SmartHomeSettings.favoriteSceneIDs] = ids
    }

    /// Moves favorites in the Favorites list, whose places count only the
    /// accessories in the home. Favorites this HomePad cannot show stay saved, after them.
    func moveFavorites(from source: IndexSet, to destination: Int) {
        var shown = favorites.map(\.id)
        shown.move(fromOffsets: source, toOffset: destination)
        let rest = favoriteAccessoryIDs.filter { !shown.contains($0) }
        settings[SmartHomeSettings.favoriteAccessoryIDs] = shown + rest
    }

    // MARK: Doorbell

    /// Which doorbell, camera and lock the person picked, as this HomePad knows them.
    var doorbell: DoorbellSettings {
        get { settings[SmartHomeSettings.doorbell].localized(by: localID(for:)) }
        set { settings[SmartHomeSettings.doorbell] = newValue }
    }
}
