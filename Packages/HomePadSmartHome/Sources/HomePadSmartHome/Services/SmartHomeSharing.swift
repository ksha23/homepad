import Foundation
import HomePadCore

/// What the Smart Home module shares with the household's other HomePads
/// (Core's shared documents, carried by Connect):
///
/// - `smarthome.favorites`, the household's: the Home app's favorite
///   accessories and scenes. They used to go through iCloud key-value
///   storage, which reaches only one Apple Account.
/// - `smarthome.homeKitDirectory`, each HomePad's own: what it calls each of
///   its HomeKit objects (`HomeKitDirectory`), so the others can turn the
///   HomeKit IDs it saves into theirs (`HomeKitIDTranslator`).
@MainActor
enum SmartHomeSharing {
    static let favoritesKind = "smarthome.favorites"
    static let directoryKind = "smarthome.homeKitDirectory"

    static func register(service: UnifiedSmartHomeService, settings: SettingsStore, in registry: ModuleRegistry) {
        // Shared by the household now. An older HomePad on the same Apple Account may still write these to iCloud.
        for key in [SmartHomeSettings.favoriteAccessoryIDs, SmartHomeSettings.favoriteSceneIDs] {
            settings.stopICloudSync(forKeyNamed: key.name)
        }
        registry.register(sharedDocument: SharedDocumentDescriptor(
            id: favoritesKind, owners: .household,
            read: { _ in readFavorites(settings) },
            apply: { _, content in applyFavorites(content, settings: settings) }
        ))
        let translator = service.homeKitIDs
        registry.register(homePadDocument: HomePadDocumentDescriptor(
            id: directoryKind,
            read: { readDirectory(translator) },
            apply: { homePad, content in
                translator.receive(content.flatMap { try? $0.decoded(as: HomeKitDirectory.self) }, from: homePad)
            }
        ))
    }

    // MARK: Favorites

    /// The favorites as saved, with each HomePad's own IDs in them.
    struct Favorites: Codable, Equatable {
        var accessories: [String]?
        var scenes: [String]?
    }

    static func readFavorites(_ settings: SettingsStore) -> SharedDocumentValue {
        let accessories = settings[SmartHomeSettings.favoriteAccessoryIDs]
        let scenes = settings[SmartHomeSettings.favoriteSceneIDs]
        guard accessories != nil || scenes != nil,
              let content = try? JSONValue(encoding: Favorites(accessories: accessories, scenes: scenes)) else { return .none }
        return .content(content)
    }

    static func applyFavorites(_ content: JSONValue?, settings: SettingsStore) {
        guard let content else {
            settings.reset(SmartHomeSettings.favoriteAccessoryIDs)
            settings.reset(SmartHomeSettings.favoriteSceneIDs)
            return
        }
        guard let favorites = try? content.decoded(as: Favorites.self) else { return }
        save(favorites.accessories, to: SmartHomeSettings.favoriteAccessoryIDs, in: settings)
        save(favorites.scenes, to: SmartHomeSettings.favoriteSceneIDs, in: settings)
    }

    /// Saves a list, or goes back to the default for nil.
    private static func save(_ ids: [String]?, to key: SettingKey<[String]?>, in settings: SettingsStore) {
        if let ids {
            settings[key] = ids
        } else {
            settings.reset(key)
        }
    }

    // MARK: HomeKit directory

    /// This HomePad's directory, or the one shared before while Apple Home
    /// has not loaded here.
    static func readDirectory(_ translator: HomeKitIDTranslator) -> SharedDocumentValue {
        guard let content = translator.sharedContent else { return .onlyThisHomePad }
        return .content(content)
    }
}
