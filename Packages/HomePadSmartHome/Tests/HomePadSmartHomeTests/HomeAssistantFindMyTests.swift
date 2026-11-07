import Foundation
import HAKit
import HAKit_Mocks
import HomePadCore
import Testing
@testable import HomePadSmartHome

/// Find My on HAKit's mock connection: trackers load, move with `state_changed`
/// over the one connection the backend already has, and ring through the right
/// action. Nothing touches a network.
@MainActor
@Suite("Home Assistant Find My", .serialized)
struct HomeAssistantFindMyTests {
    let connection = HAMockConnection()
    let backend: HomeAssistantBackend

    init() {
        let configuration = HomeAssistantConfiguration(baseURL: URL(string: "http://ha.test:8123")!, token: "test-token")
        let connection = self.connection
        backend = HomeAssistantBackend(store: .inMemory(configuration)) { _ in connection }
        backend.rebuildDelay = .zero
    }

    private func answer(_ type: HARequestType, with data: HAData) {
        for pending in connection.pendingRequests where pending.request.type == type {
            pending.completion(.success(data))
        }
        connection.pendingRequests.removeAll { $0.request.type == type }
    }

    private func pending(_ type: HARequestType) -> HARequest? {
        connection.pendingRequests.first { $0.request.type == type }?.request
    }

    /// Connects and serves the tracker fixtures.
    private func connectAndLoad() async throws {
        backend.start()
        #expect(await eventually { backend.status.isConnected })
        #expect(await eventually { pending(.rest(.get, "config")) != nil })
        answer(.rest(.get, "config"), with: Fixtures.restData("rest_config"))
        #expect(await eventually { pending("config/entity_registry/list") != nil })
        answer("config/area_registry/list", with: Fixtures.resultData("ws_result_area_registry"))
        answer("config/device_registry/list", with: Fixtures.resultData("ws_result_device_registry_trackers"))
        answer("config/entity_registry/list", with: Fixtures.resultData("ws_result_entity_registry_trackers"))
        #expect(await eventually { pending(.rest(.get, "states")) != nil })
        answer(.rest(.get, "states"), with: Fixtures.restData("rest_states_trackers"))
        #expect(await eventually { backend.trackedDevices.count == 5 })
    }

    private func device(_ entityID: String) throws -> TrackedDevice {
        try #require(backend.trackedDevices.first { $0.id == "ha:\(entityID)" })
    }

    @Test func trackersMoveWithStateChanges() async throws {
        try await connectAndLoad()
        #expect(backend.zones.map(\.name) == ["Maple Street", "Work"])
        #expect(try device("device_tracker.kyles_iphone").place == .home)
        let subscription = try #require(connection.pendingSubscriptions.first {
            $0.request.data["event_type"] as? String == "state_changed"
        })
        subscription.handler(subscription.cancellable, Fixtures.eventData("ws_event_tracker_moved"))
        #expect(await eventually { (try? device("device_tracker.kyles_iphone").place) == .zone("Work") })
        let moved = try device("device_tracker.kyles_iphone")
        #expect(moved.latitude == 43.0765)
        #expect(moved.batteryLevel == 0.79)
        // Trackers are not accessories, so the Home app never shows them.
        #expect(!backend.accessories.contains { $0.id.contains("device_tracker") })
    }

    @Test func iCloudSoundAsksForTheAccountThenCallsPlaySound() async throws {
        try await connectAndLoad()
        let iPhone = try device("device_tracker.kyles_iphone")
        let task = Task { try await backend.playSound(on: iPhone) }
        #expect(await eventually { pending("config_entries/get") != nil })
        #expect(pending("config_entries/get")?.data["domain"] as? String == "icloud")
        answer("config_entries/get", with: Fixtures.resultData("ws_result_config_entries_icloud"))
        #expect(await eventually { pending(.callService) != nil })
        let request = try #require(pending(.callService))
        #expect(request.data["domain"] as? String == "icloud")
        #expect(request.data["service"] as? String == "play_sound")
        let data = try #require(request.data["service_data"] as? [String: Any])
        #expect(data["account"] as? String == "kyle@example.com")
        #expect(data["device_name"] as? String == "Kyle\u{2019}s iPhone")
        #expect(request.shouldRetry == false)
        answer(.callService, with: .empty)
        try await task.value
    }

    @Test func companionSoundGoesStraightToNotify() async throws {
        try await connectAndLoad()
        let iPad = try device("device_tracker.kyles_ipad")
        let task = Task { try await backend.playSound(on: iPad) }
        #expect(await eventually { pending(.callService) != nil })
        #expect(pending("config_entries/get") == nil)
        let request = try #require(pending(.callService))
        #expect(request.data["domain"] as? String == "notify")
        #expect(request.data["service"] as? String == "mobile_app_kyle_s_ipad")
        answer(.callService, with: .empty)
        try await task.value
    }

    @Test func missingNotifyActionSurfacesHomeAssistantsMessage() async throws {
        try await connectAndLoad()
        let iPad = try device("device_tracker.kyles_ipad")
        let task = Task { try await backend.playSound(on: iPad) }
        #expect(await eventually { pending(.callService) != nil })
        let call = try #require(connection.pendingRequests.first { $0.request.type == .callService })
        call.completion(.failure(.external(.init(code: "service_not_found", message: "Action notify.mobile_app_kyle_s_ipad not found"))))
        await #expect(throws: SmartHomeError.self) { try await task.value }
    }

    @Test func unifiedServiceNeedsARecognizedMember() async throws {
        let services = AppServices(settings: SettingsStore(defaults: UserDefaults(suiteName: "homepad.findmy.\(UUID().uuidString)")!))
        let unified = UnifiedSmartHomeService(
            settings: services.settings, household: services.household, events: services.events,
            homeAssistant: backend, homeKit: HomeKitBackend(settings: services.settings)
        )
        try await connectAndLoad()
        #expect(unified.trackedDevices.count == 5)
        #expect(unified.zones.count == 2)
        await #expect(throws: SmartHomeError.self) {
            try await unified.playSound(onTrackedDevice: "ha:device_tracker.kyles_ipad")
        }
        #expect(pending(.callService) == nil)
        let kyle = HouseholdMember(name: "Kyle", isAdmin: true)
        services.household.add(kyle)
        services.household.recognize(kyle.id)
        await #expect(throws: SmartHomeError.self) {
            try await unified.playSound(onTrackedDevice: "ha:device_tracker.jordans_phone")
        }
        let task = Task { try await unified.playSound(onTrackedDevice: "ha:device_tracker.kyles_ipad") }
        #expect(await eventually { pending(.callService) != nil })
        answer(.callService, with: .empty)
        try await task.value
    }
}
