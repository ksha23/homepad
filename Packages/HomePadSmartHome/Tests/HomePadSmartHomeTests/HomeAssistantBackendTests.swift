import Foundation
import HAKit
import HAKit_Mocks
import HomePadCore
import Testing
@testable import HomePadSmartHome

/// Runs the Home Assistant backend against HAKit's mock connection, answering its
/// requests with the fixtures. Nothing touches a network.
@MainActor
@Suite("Home Assistant backend", .serialized)
struct HomeAssistantBackendTests {
    let connection = HAMockConnection()
    let backend: HomeAssistantBackend

    init() {
        let configuration = HomeAssistantConfiguration(baseURL: URL(string: "http://ha.test:8123")!, token: "test-token")
        let connection = self.connection
        backend = HomeAssistantBackend(store: .inMemory(configuration)) { _ in connection }
        backend.rebuildDelay = .zero
    }

    /// Answers every pending request whose type matches, in order.
    private func answer(_ type: HARequestType, with data: HAData) {
        for pending in connection.pendingRequests where pending.request.type == type {
            pending.completion(.success(data))
        }
        connection.pendingRequests.removeAll { $0.request.type == type }
    }

    private func hasRequest(_ type: HARequestType) -> Bool {
        connection.pendingRequests.contains { $0.request.type == type }
    }

    /// Connects and serves config, registries and states from the fixtures.
    private func connectAndLoad() async throws {
        backend.start()
        #expect(await eventually { backend.status.isConnected })
        #expect(await eventually { hasRequest(.rest(.get, "config")) })
        answer(.rest(.get, "config"), with: Fixtures.restData("rest_config"))
        #expect(await eventually { hasRequest("config/entity_registry/list") })
        answer("config/area_registry/list", with: Fixtures.resultData("ws_result_area_registry"))
        answer("config/device_registry/list", with: Fixtures.resultData("ws_result_device_registry"))
        answer("config/entity_registry/list", with: Fixtures.resultData("ws_result_entity_registry"))
        #expect(await eventually { hasRequest(.rest(.get, "states")) })
        answer(.rest(.get, "states"), with: Fixtures.restData("rest_states"))
        #expect(await eventually { backend.accessories.count == 20 })
    }

    private var stateChangedSubscription: HAMockConnection.PendingSubscription? {
        connection.pendingSubscriptions.first { $0.request.data["event_type"] as? String == "state_changed" }
    }

    @Test func subscribesToStateChangesAndRegistryUpdates() {
        backend.start()
        let types = connection.pendingSubscriptions.compactMap { $0.request.data["event_type"] as? String }
        #expect(types == ["state_changed"] + HARegistry.updateEventTypes)
        #expect(connection.pendingSubscriptions.allSatisfy { $0.request.type == .subscribeEvents })
    }

    @Test func initialLoadUsesRoomsAndServerConfig() async throws {
        try await connectAndLoad()
        #expect(backend.serverConfig?.locationName == "Maple Street")
        #expect(backend.accessories.first { $0.id == "ha:light.kitchen" }?.room == "Kitchen")
        #expect(backend.accessories.first { $0.id == "ha:climate.hallway" }?.state.temperatureUnit == .fahrenheit)
        #expect(backend.cameras.count == 2)
        #expect(backend.isConfigured)
    }

    @Test func stateChangedEventUpdatesTheAccessory() async throws {
        try await connectAndLoad()
        let subscription = try #require(stateChangedSubscription)
        subscription.handler(subscription.cancellable, Fixtures.eventData("ws_event_light_off"))
        #expect(await eventually { backend.accessories.first { $0.id == "ha:light.kitchen" }?.state.isOn == false })
        subscription.handler(subscription.cancellable, Fixtures.eventData("ws_event_entity_removed"))
        #expect(await eventually { !backend.accessories.contains { $0.id == "ha:switch.coffee" } })
    }

    @Test func doorbellEventReportsItsCamera() async throws {
        try await connectAndLoad()
        var rang: [String?] = []
        backend.onDoorbell = { rang.append($0) }
        let subscription = try #require(stateChangedSubscription)
        subscription.handler(subscription.cancellable, Fixtures.eventData("ws_event_doorbell_restored"))
        #expect(rang.isEmpty)
        subscription.handler(subscription.cancellable, Fixtures.eventData("ws_event_doorbell_ring"))
        #expect(rang == ["ha:camera.front_door"])
    }

    @Test func burstOfRegistryEventsReloadsOnce() async throws {
        try await connectAndLoad()
        backend.registryReloadDelay = .milliseconds(50)
        let subscription = try #require(connection.pendingSubscriptions.first {
            $0.request.data["event_type"] as? String == "entity_registry_updated"
        })
        for _ in 0..<3 {
            subscription.handler(subscription.cancellable, Fixtures.eventData("ws_event_light_off"))
        }
        #expect(await eventually { hasRequest("config/entity_registry/list") })
        try await Task.sleep(for: .milliseconds(200))
        #expect(connection.pendingRequests.filter { $0.request.type == "config/entity_registry/list" }.count == 1)
        answer("config/area_registry/list", with: Fixtures.resultData("ws_result_area_registry"))
        answer("config/device_registry/list", with: Fixtures.resultData("ws_result_device_registry"))
        answer("config/entity_registry/list", with: Fixtures.resultData("ws_result_entity_registry"))
    }

    @Test func performSendsCallService() async throws {
        try await connectAndLoad()
        let accessory = try #require(backend.accessories.first { $0.id == "ha:light.kitchen" })
        let task = Task { try await backend.perform(.setBrightness(0.5), on: accessory) }
        #expect(await eventually { hasRequest(.callService) })
        let request = try #require(connection.pendingRequests.first { $0.request.type == .callService }?.request)
        #expect(request.data["domain"] as? String == "light")
        #expect(request.data["service"] as? String == "turn_on")
        #expect((request.data["service_data"] as? [String: Any])?["brightness_pct"] as? Double == 50)
        #expect((request.data["target"] as? [String: Any])?["entity_id"] as? String == "light.kitchen")
        answer(.callService, with: .empty)
        try await task.value
    }

    @Test func failedCallSurfacesHomeAssistantsMessage() async throws {
        try await connectAndLoad()
        let task = Task { try await backend.callService(domain: "lock", service: "unlock", data: ["entity_id": "lock.garage"]) }
        #expect(await eventually { hasRequest(.callService) })
        let pending = try #require(connection.pendingRequests.first { $0.request.type == .callService })
        pending.completion(.failure(.external(.init(code: "service_validation_error", message: "Entity lock.garage is not available"))))
        await #expect(throws: SmartHomeError.self) { try await task.value }
    }

    @Test func notConfiguredStaysQuiet() {
        let backend = HomeAssistantBackend(store: .inMemory(nil)) { _ in HAMockConnection() }
        backend.start()
        #expect(backend.status == .notConfigured)
        #expect(!backend.isConfigured)
    }

    @Test func rejectedTokenIsReported() async {
        // The mock would otherwise jump back to connecting when the initial requests go out.
        connection.automaticallyTransitionToConnecting = false
        backend.start()
        connection.setState(.disconnected(reason: .rejected), waitForQueue: false)
        #expect(await eventually { backend.status == .failed("Home Assistant rejected the access token.") })
    }

    @Test func waitingToReconnectIsReported() async {
        connection.automaticallyTransitionToConnecting = false
        backend.start()
        let retry = Date().addingTimeInterval(10)
        connection.setState(.disconnected(reason: .waitingToReconnect(lastError: nil, atLatest: retry, retryCount: 2)), waitForQueue: false)
        #expect(await eventually { backend.status == .reconnecting(retryAt: retry) })
    }

    @Test func rawCommandReturnsTheResult() async throws {
        try await connectAndLoad()
        let task = Task { try await backend.sendCommand("config_entries/get", data: ["domain": "music_assistant"]) }
        #expect(await eventually { hasRequest("config_entries/get") })
        let request = try #require(connection.pendingRequests.first { $0.request.type == "config_entries/get" }?.request)
        #expect(request.data["domain"] as? String == "music_assistant")
        #expect(request.shouldRetry == false)
        answer("config_entries/get", with: Fixtures.resultData("ws_result_config_entries_music_assistant"))
        let entries = try await task.value.arrayValue ?? []
        #expect(entries.first?["entry_id"]?.stringValue == "01JA0000000000000000000001")
    }

    @Test func actionResponseKeepsItsShape() async throws {
        try await connectAndLoad()
        let task = Task {
            try await backend.sendCommand("call_service", data: [
                "domain": "music_assistant", "service": "get_queue", "service_data": [:],
                "target": ["entity_id": "media_player.kitchen_homepod"], "return_response": true,
            ])
        }
        #expect(await eventually { hasRequest(.callService) })
        let request = try #require(connection.pendingRequests.first { $0.request.type == .callService }?.request)
        #expect(request.data["return_response"] as? Bool == true)
        answer(.callService, with: Fixtures.resultData("ws_result_call_service_get_queue"))
        let result = try await task.value
        #expect(result["response"]?["media_player.kitchen_homepod"]?["current_item"]?["name"]?.stringValue == "Taylor Swift - Anti-Hero")
    }

    // MARK: Camera feeds

    /// Answers the capabilities request the next feed makes.
    private func answerCapabilities(_ fixture: String = "ws_result_camera_capabilities") async {
        #expect(await eventually { hasRequest("camera/capabilities") })
        answer("camera/capabilities", with: Fixtures.resultData(fixture))
    }

    @Test func cameraFeedsFallBackInOrder() async throws {
        try await connectAndLoad()
        let camera = try #require(backend.cameras.first { $0.id == "ha:camera.front_door" })

        let full = Task { await backend.feed(for: camera, purpose: .fullScreen, excluding: []) }
        await answerCapabilities()
        guard case .webRTC(let source) = await full.value else {
            Issue.record("full screen starts with WebRTC")
            return
        }
        #expect(source.entityID == "camera.front_door")
        #expect(source.receivesAudio)
        #expect(source.offersTalk, "two-way audio offers talk")

        let grid = Task { await backend.feed(for: camera, purpose: .grid, excluding: []) }
        await answerCapabilities()
        guard case .webRTC(let gridSource) = await grid.value else {
            Issue.record("grids start with WebRTC")
            return
        }
        #expect(!gridSource.receivesAudio && !gridSource.offersTalk, "a grid asks for video alone")

        let hls = Task { await backend.feed(for: camera, purpose: .fullScreen, excluding: [.webRTC]) }
        await answerCapabilities()
        #expect(await eventually { hasRequest("camera/stream") })
        answer("camera/stream", with: Fixtures.resultData("ws_result_camera_stream"))
        guard case .hls(let url) = await hls.value else {
            Issue.record("HLS comes after WebRTC")
            return
        }
        #expect(url.absoluteString == "http://ha.test:8123/api/hls/7f3a9c/master_playlist.m3u8")

        let mjpeg = Task { await backend.feed(for: camera, purpose: .fullScreen, excluding: [.webRTC, .hls]) }
        await answerCapabilities()
        guard case .mjpeg(let request) = await mjpeg.value else {
            Issue.record("MJPEG comes after HLS")
            return
        }
        #expect(request.url?.path == "/api/camera_proxy_stream/camera.front_door")
        #expect(!hasRequest("camera/stream"), "HLS is not asked for once it failed")

        let stills = Task { await backend.feed(for: camera, purpose: .fullScreen, excluding: [.webRTC, .hls, .mjpeg]) }
        await answerCapabilities()
        guard case .stills = await stills.value else {
            Issue.record("stills come last")
            return
        }
    }

    @Test func serverWithoutCapabilitiesUsesTheStreamFeature() async throws {
        try await connectAndLoad()
        let camera = try #require(backend.cameras.first { $0.id == "ha:camera.front_door" })
        let full = Task { await backend.feed(for: camera, purpose: .fullScreen, excluding: []) }
        #expect(await eventually { hasRequest("camera/capabilities") })
        // Before 2024.11 Home Assistant does not know the command.
        for pending in connection.pendingRequests where pending.request.type == "camera/capabilities" {
            pending.completion(.failure(.external(.init(code: "unknown_command", message: "Unknown command."))))
        }
        connection.pendingRequests.removeAll { $0.request.type == "camera/capabilities" }
        #expect(await eventually { hasRequest("camera/stream") })
        answer("camera/stream", with: Fixtures.resultData("ws_result_camera_stream"))
        guard case .hls = await full.value else {
            Issue.record("the stream feature still means HLS")
            return
        }
    }
}
