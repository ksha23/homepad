import Foundation
import HAKit
import HAKit_Mocks
import HomePadCore
import Testing
@testable import HomePadSmartHome

@MainActor
@Suite("Unified smart home service", .serialized)
struct UnifiedSmartHomeServiceTests {
    let services: AppServices
    let service: UnifiedSmartHomeService

    init() {
        let suite = "homepad.smarthome.tests.\(UUID().uuidString)"
        services = AppServices(settings: SettingsStore(defaults: UserDefaults(suiteName: suite)!))
        service = UnifiedSmartHomeService(
            settings: services.settings, household: services.household, events: services.events,
            homeAssistant: HomeAssistantBackend(store: .inMemory(nil)) { _ in HAMockConnection() },
            homeKit: HomeKitBackend(settings: services.settings)
        )
    }

    @Test func demoFillsInWhenNothingIsConfigured() {
        #expect(service.isShowingDemo)
        #expect(service.connectedBackends == [.demo])
        #expect(!service.accessories.isEmpty)
        #expect(service.accessories.allSatisfy { $0.id.hasPrefix("demo:") })
        #expect(service.cameras.count == 4)
        #expect(service.homeName == "My Home")
    }

    @Test func installsAsTheAppService() {
        SmartHomeModule.register(services: services, registry: ModuleRegistry())
        #expect(services.smartHome is UnifiedSmartHomeService)
    }

    @Test func theCamerasLinkOpensHomeOnEveryCamera() throws {
        let registry = ModuleRegistry()
        SmartHomeModule.register(services: services, registry: registry)
        let installed = try #require(services.smartHome as? UnifiedSmartHomeService)
        #expect(!installed.requestsAllCameras)
        #expect(registry.followingRedirect("cameras") == "home")
        #expect(installed.requestsAllCameras)
    }

    @Test func layoutAndFavoritesFollowEverySettingsWrite() {
        #expect(service.layout.hiddenRooms.isEmpty)
        var layout = HomeLayout()
        layout.hiddenRooms = ["Kitchen"]
        services.settings[SmartHomeSettings.layout] = layout
        #expect(service.layout.hiddenRooms == ["Kitchen"])
        services.settings[SmartHomeSettings.favoriteSceneIDs] = ["demo:scene.movie"]
        #expect(service.favoriteSceneIDs == ["demo:scene.movie"])
        service.setFavoriteScene("demo:scene.dinner", isFavorite: true)
        #expect(service.favoriteSceneIDs == ["demo:scene.movie", "demo:scene.dinner"])
        service.setFavorite("demo:light.kitchen", isFavorite: false)
        #expect(!service.favoriteAccessoryIDs.contains("demo:light.kitchen"))
    }

    @Test func roomsIncludeRoomsWithOnlyCameras() {
        #expect(service.cameras.contains { $0.room == "Outside" })
        #expect(!service.accessories.contains { $0.room == "Outside" })
        #expect(service.orderedRooms.contains("Outside"))
    }

    @Test func registersEverySurface() {
        let registry = ModuleRegistry()
        SmartHomeModule.register(services: services, registry: registry)
        #expect(registry.app("home") != nil)
        #expect(registry.app("dashboards") != nil)
        // Cameras live in the Home app. Their old app ID opens them there.
        #expect(registry.app("cameras") == nil)
        #expect(registry.redirect("cameras")?.appID == "home")
        #expect(registry.overlays.contains { $0.id == "smarthome.doorbell" })
        #expect(registry.controls.map(\.id).sorted() == ["smarthome.accessories", "smarthome.scenes"])
        #expect(Set(registry.widgets.map(\.id)) == ["smarthome.camera", "smarthome.favorites", "smarthome.scenes"])
        #expect(registry.settingsPanes.contains { $0.id == "smarthome" })
        let tool = registry.tools.first { $0.name == "home_assistant_service" }
        #expect(tool?.requiresRecognizedMember == true)
    }

    @Test func commandsRouteByPrefix() async throws {
        try await service.perform(.setPower(false), on: "demo:light.kitchen")
        #expect(service.accessory("demo:light.kitchen")?.state.isOn == false)
        await #expect(throws: SmartHomeError.self) { try await service.perform(.toggle, on: "ha:light.nowhere") }
    }

    @Test func guestsCannotUnlockWithoutConfirmation() async throws {
        #expect(services.household.isGuest)
        await #expect(throws: SmartHomeError.self) { try await service.perform(.unlock, on: "demo:lock.front") }
        #expect(service.accessory("demo:lock.front")?.state.lockState == .locked)
        await #expect(throws: SmartHomeError.self) { try await service.perform(.open, on: "demo:garage.main") }
        try await service.perform(.unlock, on: "demo:lock.front", confirmed: true)
        #expect(service.accessory("demo:lock.front")?.state.lockState == .unlocked)
        try await service.perform(.lock, on: "demo:lock.front")
        #expect(service.accessory("demo:lock.front")?.state.lockState == .locked, "locking never needs confirmation")
    }

    @Test func recognizedMembersCanUnlock() async throws {
        let member = HouseholdMember(name: "Kyle")
        services.household.add(member)
        services.household.recognize(member.id)
        try await service.perform(.unlock, on: "demo:lock.front")
        #expect(service.accessory("demo:lock.front")?.state.lockState == .unlocked)
    }

    @Test func layoutHidesRoomsAndPinsItems() {
        var layout = service.layout
        layout.setRoom("Kitchen", visible: false)
        service.layout = layout
        #expect(!service.accessories.contains { $0.room == "Kitchen" })
        #expect(service.allAccessories.contains { $0.room == "Kitchen" })
        layout.setItem("demo:light.kitchen", room: "Kitchen", visible: true)
        service.layout = layout
        #expect(service.accessories.contains { $0.id == "demo:light.kitchen" })
        layout.setItem("demo:fan.office", room: "Office", visible: false)
        service.layout = layout
        #expect(!service.accessories.contains { $0.id == "demo:fan.office" })
    }

    @Test func favoritesDefaultThenPersist() {
        let defaults = service.favoriteAccessoryIDs
        #expect(defaults.first == "demo:climate.living", "climate comes first")
        #expect(defaults.count == 6)
        service.setFavorite("demo:switch.coffee", isFavorite: true)
        #expect(service.favoriteAccessoryIDs == defaults + ["demo:switch.coffee"])
        service.setFavorite("demo:climate.living", isFavorite: false)
        #expect(!service.favoriteAccessoryIDs.contains("demo:climate.living"))
        service.setFavoriteScene("demo:scene.movie", isFavorite: true)
        #expect(service.favoriteScenes.last?.id == "demo:scene.movie")
    }

    /// The Home app shows only scenes the person picked, and none at first. The
    /// widget and Control Center tile still offer scenes, favorites first.
    @Test func noFavoriteScenesUntilPicked() {
        #expect(service.favoriteScenes.isEmpty)
        #expect(service.scenesFavoritesFirst.map(\.id) == service.scenes.map(\.id))
        service.setFavoriteScene("demo:scene.movie", isFavorite: true)
        #expect(service.favoriteScenes.map(\.id) == ["demo:scene.movie"])
        #expect(service.scenesFavoritesFirst.first?.id == "demo:scene.movie")
        #expect(service.scenesFavoritesFirst.count == service.scenes.count)
        service.setFavoriteScene("demo:scene.movie", isFavorite: false)
        #expect(service.favoriteScenes.isEmpty)
    }

    @Test func doorbellPostsEventForTheDoorbellCamera() async {
        let stream = services.events.stream()
        service.doorbellRang(cameraID: nil)
        var iterator = stream.makeAsyncIterator()
        guard case .doorbellRang(let cameraID) = await iterator.next() else {
            Issue.record("expected a doorbell event")
            return
        }
        #expect(cameraID == "demo:camera.front")
        #expect(service.doorbellLock?.id == "demo:lock.front", "the lock in the doorbell camera's room")
    }

    @Test func doorbellPresenterShowsAndDismisses() async {
        let presenter = DoorbellPresenter(settings: services.settings, events: services.events)
        presenter.startListening()
        services.events.post(.doorbellRang(cameraID: "demo:camera.front"))
        #expect(await eventually { presenter.ring?.cameraID == "demo:camera.front" })
        presenter.dismiss()
        #expect(presenter.ring == nil)
    }

    @Test func showControlsOpensTheHomeAppOnTheAccessory() async {
        let stream = services.events.stream()
        service.showControls(for: "demo:climate.living")
        #expect(service.requestedDetailID == "demo:climate.living")
        var iterator = stream.makeAsyncIterator()
        guard case .openApp(let appID) = await iterator.next() else {
            Issue.record("expected the Home app to open")
            return
        }
        #expect(appID == SmartHomeModule.homeAppID)
    }

    @Test func dragsSetDemoLevels() async throws {
        let blinds = try #require(service.accessory("demo:cover.bedroom"))
        try await service.perform(AccessoryPresentation.levelCommand(0.75, for: blinds), on: blinds.id)
        #expect(service.accessory("demo:cover.bedroom")?.state.position == 0.75)
        let desk = try #require(service.accessory("demo:light.desk"))
        #expect(AccessoryPresentation.level(of: desk) == 0, "an off lamp starts the drag at zero")
        try await service.perform(AccessoryPresentation.levelCommand(0.4, for: desk), on: desk.id)
        #expect(service.accessory("demo:light.desk")?.state.isOn == true)
        #expect(service.accessory("demo:light.desk")?.state.brightness == 0.4)
    }

    @Test func rawServiceCallsNeedHomeAssistant() async {
        await #expect(throws: SmartHomeError.self) {
            try await service.callService(domain: "light", service: "turn_on", data: ["entity_id": "light.kitchen"])
        }
    }

    @Test func demoHistoryAndSnapshot() async throws {
        let history = await service.history(for: "demo:sensor.office_temp")
        #expect(history.count > 10)
        let jpeg = try await service.snapshot(cameraID: "demo:camera.yard")
        #expect(jpeg?.prefix(2) == Data([0xFF, 0xD8]))
    }

    @Test func rawCommandsNeedHomeAssistantAndPassThePolicy() async throws {
        await #expect(throws: SmartHomeError.self) { try await service.sendCommand("config_entries/get", data: [:]) }
        let configured = UnifiedSmartHomeService(
            settings: services.settings, household: services.household, events: services.events,
            homeAssistant: HomeAssistantBackend(store: .inMemory(HomeAssistantConfiguration(
                baseURL: URL(string: "http://ha.test:8123")!, token: "t"))) { _ in HAMockConnection() },
            homeKit: HomeKitBackend(settings: services.settings)
        )
        do {
            _ = try await configured.sendCommand("config/entity_registry/update", data: [:])
            Issue.record("Writing commands must be refused")
        } catch SmartHomeError.unsupported {}
        do {
            _ = try await configured.sendCommand("call_service", data: [
                "domain": "lock", "service": "unlock", "target": ["entity_id": "lock.front"], "return_response": true,
            ])
            Issue.record("Guests must not unlock through a raw command")
        } catch SmartHomeError.requiresRecognizedMember {}
    }
}

