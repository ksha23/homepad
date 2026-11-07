import Foundation
import HAKit
import HAKit_Mocks
import HomePadCore
import Testing
@testable import HomePadSmartHome

/// The service on this HomePad (the office, the M4) with favorites, a layout,
/// a doorbell and widget picks saved on another HomePad (the kitchen, the
/// 11-inch), whose HomeKit IDs for the same objects differ. The demo
/// accessories stand in for this HomePad's own.
@MainActor
@Suite("Saved IDs from another HomePad", .serialized)
struct SavedIDTranslationTests {
    private typealias Entry = HomeKitDirectory.Entry
    let services: AppServices
    let service: UnifiedSmartHomeService

    init() {
        let suite = "homepad.smarthome.saved-ids.\(UUID().uuidString)"
        services = AppServices(settings: SettingsStore(defaults: UserDefaults(suiteName: suite)!))
        service = UnifiedSmartHomeService(
            settings: services.settings, household: services.household, events: services.events,
            homeAssistant: HomeAssistantBackend(store: .inMemory(nil)) { _ in HAMockConnection() },
            homeKit: HomeKitBackend(settings: services.settings)
        )
        service.homeKitIDs.updateLocal(directory { $0 })
        service.homeKitIDs.receive(directory(Self.kitchenID), from: "kitchen")
    }

    /// The kitchen's ID for one of this HomePad's objects.
    static func kitchenID(_ id: String) -> String {
        "hk:kitchen-\(id)"
    }

    /// A directory of the home as the service shows it, under `id`'s IDs.
    private func directory(_ id: (String) -> String) -> HomeKitDirectory {
        let accessories = service.allAccessories.map {
            Entry(id: id($0.id), kind: $0.kind.rawValue, home: "Home", room: $0.room, name: $0.name, accessory: $0.name)
        }
        let cameras = service.allCameras.map {
            Entry(id: id($0.id), kind: HomeKitDirectory.Kind.camera, home: "Home", room: $0.room, name: $0.name)
        }
        let scenes = service.scenes.map {
            Entry(id: id($0.id), kind: HomeKitDirectory.Kind.scene, home: "Home", name: $0.name)
        }
        return HomeKitDirectory(entries: accessories + cameras + scenes)
    }

    @Test func favoritesSavedOnTheOtherHomePadShowHere() {
        let saved = ["demo:light.desk", "demo:lock.front", "demo:climate.living"].map(Self.kitchenID)
        services.settings[SmartHomeSettings.favoriteAccessoryIDs] = saved
        #expect(service.favorites.map(\.id) == ["demo:light.desk", "demo:lock.front", "demo:climate.living"])
        #expect(service.accessory(Self.kitchenID("demo:lock.front"))?.name == "Front Door")
    }

    @Test func aFavoriteSavedOnBothHomePadsShowsOnce() {
        services.settings[SmartHomeSettings.favoriteAccessoryIDs] = [Self.kitchenID("demo:light.desk"), "demo:light.desk"]
        #expect(service.favoriteAccessoryIDs == ["demo:light.desk"])
        #expect(service.favorites.count == 1)
    }

    @Test func changingFavoritesHereKeepsWhatThisHomePadCannotShow() {
        let unknown = "hk:kitchen-something-only-it-has"
        services.settings[SmartHomeSettings.favoriteAccessoryIDs] = [Self.kitchenID("demo:light.desk"), unknown,
                                                                      Self.kitchenID("demo:lock.front")]
        // Unstarring the kitchen's lamp here takes it off, under either ID.
        service.setFavorite("demo:light.desk", isFavorite: false)
        #expect(service.favorites.map(\.id) == ["demo:lock.front"])
        // Starring it again adds this HomePad's ID, and the unknown one stays saved.
        service.setFavorite("demo:light.desk", isFavorite: true)
        #expect(service.favorites.map(\.id) == ["demo:lock.front", "demo:light.desk"])
        #expect(services.settings[SmartHomeSettings.favoriteAccessoryIDs] == [unknown, "demo:lock.front", "demo:light.desk"])

        // Moving counts only the favorites shown.
        service.moveFavorites(from: IndexSet(integer: 1), to: 0)
        #expect(service.favorites.map(\.id) == ["demo:light.desk", "demo:lock.front"])
        #expect(services.settings[SmartHomeSettings.favoriteAccessoryIDs] == ["demo:light.desk", "demo:lock.front", unknown])
    }

    @Test func favoriteScenesSavedOnTheOtherHomePadShowHere() {
        services.settings[SmartHomeSettings.favoriteSceneIDs] = [Self.kitchenID("demo:scene.night")]
        #expect(service.favoriteScenes.map(\.id) == ["demo:scene.night"])
        #expect(service.scenesFavoritesFirst.first?.id == "demo:scene.night")
        service.setFavoriteScene("demo:scene.night", isFavorite: false)
        #expect(service.favoriteScenes.isEmpty)
    }

    @Test func theLayoutSavedOnTheOtherHomePadAppliesHere() throws {
        var layout = HomeLayout()
        layout.hiddenIDs = [Self.kitchenID("demo:light.desk")]
        layout.tileSizes = [Self.kitchenID("demo:fan.office"): .wide]
        services.settings[SmartHomeSettings.layout] = layout
        service.rebuild()
        #expect(!service.accessories.contains { $0.id == "demo:light.desk" })
        let fan = try #require(service.allAccessories.first { $0.id == "demo:fan.office" })
        #expect(service.layout.tileSize(for: fan) == .wide)

        // Showing it again here takes off the kitchen's entry too.
        let lamp = try #require(service.allAccessories.first { $0.id == "demo:light.desk" })
        service.layout.setItem(lamp.id, room: lamp.room, visible: true)
        #expect(service.accessories.contains { $0.id == "demo:light.desk" })
        // A tile size set here wins over the kitchen's for the same accessory.
        service.layout.tileSizes[fan.id] = .small
        #expect(service.layout.tileSize(for: fan) == .small)
    }

    @Test func theDoorbellPickedOnTheOtherHomePadRingsHere() {
        var doorbell = DoorbellSettings()
        doorbell.cameraID = Self.kitchenID("demo:camera.yard")
        doorbell.lockID = Self.kitchenID("demo:lock.ultra")
        services.settings[SmartHomeSettings.doorbell] = doorbell
        #expect(service.doorbellCameraID == "demo:camera.yard")
        #expect(service.doorbellLock?.id == "demo:lock.ultra")
        #expect(service.camera(Self.kitchenID("demo:camera.yard"))?.name == "Back Yard")
    }

    @Test func commandsAndScenesTakeTheOtherHomePadsIDs() async throws {
        try await service.perform(.setPower(true), on: Self.kitchenID("demo:light.desk"))
        #expect(service.accessory("demo:light.desk")?.state.isOn == true)
        try await service.activateScene(Self.kitchenID("demo:scene.night"))
    }

    @Test func aWidgetsAccessoriesPickedOnTheOtherHomePadShowHere() {
        let chosen = service.localIDs(for: [Self.kitchenID("demo:light.desk"), Self.kitchenID("demo:lock.front")])
        let shown = FavoritesWidgetChoice.shown(chosen, favorites: service.favorites, accessories: service.accessories)
        #expect(shown.map(\.name) == ["Desk Lamp", "Front Door"])
    }

    @Test func favoritesTravelWithTheSharedSetup() {
        services.settings[SmartHomeSettings.favoriteAccessoryIDs] = ["hk:a", "hk:b"]
        let read = SmartHomeSharing.readFavorites(services.settings)
        guard case .content(let content) = read else {
            Issue.record("Saved favorites are shared")
            return
        }
        // Another HomePad applies them, and reads back exactly what it applied.
        let other = SettingsStore(defaults: UserDefaults(suiteName: "homepad.smarthome.other.\(UUID().uuidString)")!)
        SmartHomeSharing.applyFavorites(content, settings: other)
        #expect(other[SmartHomeSettings.favoriteAccessoryIDs] == ["hk:a", "hk:b"])
        #expect(other[SmartHomeSettings.favoriteSceneIDs] == nil)
        #expect(SmartHomeSharing.readFavorites(other) == read)
        // A deletion goes back to the automatic favorites.
        SmartHomeSharing.applyFavorites(nil, settings: other)
        #expect(!other.contains(SmartHomeSettings.favoriteAccessoryIDs))
        #expect(SmartHomeSharing.readFavorites(other) == .none)
    }

    @Test func registersTheFavoritesAndTheDirectory() {
        let registry = ModuleRegistry()
        SmartHomeModule.register(services: services, registry: registry)
        #expect(registry.sharedDocuments.map(\.id) == ["smarthome.favorites"])
        #expect(registry.homePadDocuments.map(\.id) == ["smarthome.homeKitDirectory"])
    }
}
