import Foundation
import HAKit
import HAKit_Mocks
import HomePadCore
import SwiftUI
import Testing
@testable import HomePadSmartHome

/// This HomePad as a device in Home Assistant, end to end on HAKit's mock
/// connection and a fake `mobile_app` transport: registering once, renaming,
/// registering again without a duplicate, throttled updates, commands over the
/// push channel, turning off and removing. Nothing touches a network.
@MainActor
@Suite("Home Assistant device", .serialized)
struct HomeAssistantDeviceTests {
    /// The sensors' inputs, changed by the tests.
    final class Inputs {
        var value = MobileAppSensorInputs.sample
    }

    let services: AppServices
    let connection = HAMockConnection()
    let registry = ModuleRegistry()
    let transport = FakeMobileAppTransport()
    let store = MobileAppRegistrationStore.inMemory()
    let service: UnifiedSmartHomeService
    let inputs = Inputs()

    init() {
        let suite = "homepad.smarthome.device.tests.\(UUID().uuidString)"
        services = AppServices(settings: SettingsStore(defaults: UserDefaults(suiteName: suite)!))
        services.settings[CoreSettings.roomName] = "Kitchen"
        let configuration = HomeAssistantConfiguration(baseURL: URL(string: "http://ha.test:8123")!, token: "test-token")
        let connection = self.connection
        let backend = HomeAssistantBackend(store: .inMemory(configuration)) { _ in connection }
        backend.rebuildDelay = .zero
        service = UnifiedSmartHomeService(
            settings: services.settings, household: services.household, events: services.events,
            homeAssistant: backend, homeKit: HomeKitBackend(settings: services.settings)
        )
        registry.register(app: AppDescriptor(id: "recipes", title: "Recipes", systemImage: "fork.knife", category: .kitchen) { EmptyView() })
        registry.register(face: FaceDescriptor(id: "faces.night", title: "Night", systemImage: "moon") { EmptyView() })
    }

    private func makeDevice(store: MobileAppRegistrationStore? = nil) -> HomeAssistantDevice {
        let device = HomeAssistantDevice(services: services, registry: registry, smartHome: service,
                                         transport: transport, store: store ?? self.store, info: .test)
        let inputs = self.inputs
        device.inputsOverride = { inputs.value }
        return device
    }

    /// Connects Home Assistant and turns the device on.
    private func startActive(_ device: HomeAssistantDevice) async {
        if !service.homeAssistant.status.isConnected {
            service.homeAssistant.start()
            #expect(await eventually { service.homeAssistant.status.isConnected })
        }
        device.isEnabled = true
        device.start()
        #expect(await eventually { device.status == .active })
    }

    private var pushChannel: HAMockConnection.PendingSubscription? {
        connection.pendingSubscriptions.last { $0.request.type == .webSocket("mobile_app/push_notification_channel") }
    }

    private func answer(_ type: HARequestType, with data: HAData) {
        for pending in connection.pendingRequests where pending.request.type == type {
            pending.completion(.success(data))
        }
        connection.pendingRequests.removeAll { $0.request.type == type }
    }

    private func stored(webhookID: String, deviceName: String) -> MobileAppRegistration.Stored {
        MobileAppRegistration.Stored(webhookID: webhookID, instanceURL: "http://ha.test:8123", deviceName: deviceName,
                                     appVersion: MobileAppDeviceInfo.test.appVersion, registeredAt: Date(timeIntervalSince1970: 0))
    }

    @Test func registersOnceAsItsOwnNamedDevice() async throws {
        let device = makeDevice()
        await startActive(device)

        #expect(transport.registrations.count == 1)
        let body = try #require(transport.registrations.first)
        #expect(body["device_id"] == "test-device")
        #expect(body["device_name"] == "Kitchen HomePad")
        #expect(body["app_id"] == "com.ksha23.homepad")
        #expect(body["os_version"] == "26.1")
        #expect(body["supports_encryption"] == false)
        #expect(body["app_data"]?["push_websocket_channel"] == true)
        let sensors = transport.messages(ofType: "register_sensor")
        #expect(sensors.count == MobileAppSensor.allCases.count)
        #expect(transport.messages.allSatisfy { $0.webhookID == "fake-webhook-1" })
        #expect(device.notifyAction == "notify.mobile_app_kitchen_homepad")
        #expect(store.load()?.webhookID == "fake-webhook-1")

        let channel = try #require(pushChannel)
        #expect(channel.request.data["webhook_id"] as? String == "fake-webhook-1")
        #expect(channel.request.data["support_confirm"] as? Bool == false)

        // The next launch keeps the registration and only registers the sensors again.
        let relaunched = makeDevice()
        relaunched.start()
        #expect(await eventually { relaunched.status == .active })
        #expect(transport.registrations.count == 1)
        #expect(transport.messages(ofType: "register_sensor").count == 2 * MobileAppSensor.allCases.count)
    }

    @Test func aNewRoomRenamesTheDevice() async throws {
        store.save(stored(webhookID: "fake-webhook-1", deviceName: "HomePad"))
        let device = makeDevice()
        await startActive(device)
        #expect(transport.registrations.isEmpty)
        #expect(transport.messages(ofType: "update_registration").first?["data"]?["device_name"] == "Kitchen HomePad")
        #expect(transport.messages(ofType: "update_registration").first?["data"]?["app_data"]?["push_websocket_channel"] == true)

        services.settings[CoreSettings.roomName] = "Office"
        #expect(await eventually { device.registration?.deviceName == "Office HomePad" })
        #expect(transport.messages(ofType: "update_registration").last?["data"]?["device_name"] == "Office HomePad")
        #expect(device.notifyAction == "notify.mobile_app_office_homepad")
        #expect(transport.registrations.isEmpty)
    }

    @Test func aDeletedRegistrationRegistersTheSameDeviceAgain() async throws {
        store.save(stored(webhookID: "deleted-webhook", deviceName: "Kitchen HomePad"))
        transport.goneWebhooks = ["deleted-webhook"]
        let device = makeDevice()
        await startActive(device)
        #expect(transport.registrations.count == 1)
        #expect(device.registration?.webhookID == "fake-webhook-1")
        #expect(pushChannel?.request.data["webhook_id"] as? String == "fake-webhook-1")

        // Deleted again while reporting: the next update finds out and registers again.
        transport.goneWebhooks.insert("fake-webhook-1")
        device.throttle.minimumInterval = 0
        inputs.value.presence.proximity = .near
        device.inputsChanged()
        #expect(await eventually { device.registration?.webhookID == "fake-webhook-2" && device.status == .active })
        #expect(transport.registrations.count == 2)
        #expect(transport.registrations.allSatisfy { $0["device_id"] == "test-device" })
    }

    @Test func changesGoOutThrottled() async throws {
        let device = makeDevice()
        await startActive(device)
        device.throttle.minimumInterval = 0.3
        inputs.value.presence.proximity = .near
        device.inputsChanged()
        #expect(await eventually { transport.messages(ofType: "update_sensor_states").count == 1 })
        let first = try #require(transport.messages(ofType: "update_sensor_states").first)
        #expect(first["data"]?.arrayValue?.map { $0["unique_id"] } == ["proximity"])

        // A step back and forth within the interval sends nothing.
        inputs.value.presence.proximity = .mid
        device.inputsChanged()
        inputs.value.presence.proximity = .near
        device.inputsChanged()
        try await Task.sleep(for: .milliseconds(600))
        #expect(transport.messages(ofType: "update_sensor_states").count == 1)

        inputs.value.recognizedName = nil
        device.inputsChanged()
        #expect(await eventually { transport.messages(ofType: "update_sensor_states").count == 2 })
        #expect(transport.messages(ofType: "update_sensor_states").last?["data"]?.arrayValue?.first?["state"] == "Guest")
    }

    @Test func pushNotificationsRunCommands() async throws {
        let device = makeDevice()
        await startActive(device)
        // Home Assistant's cameras, so kiosk_show_camera finds the front door.
        #expect(await eventually { connection.pendingRequests.contains { $0.request.type == .rest(.get, "config") } })
        answer(.rest(.get, "config"), with: Fixtures.restData("rest_config"))
        #expect(await eventually { connection.pendingRequests.contains { $0.request.type == "config/entity_registry/list" } })
        answer("config/area_registry/list", with: Fixtures.resultData("ws_result_area_registry"))
        answer("config/device_registry/list", with: Fixtures.resultData("ws_result_device_registry"))
        answer("config/entity_registry/list", with: Fixtures.resultData("ws_result_entity_registry"))
        #expect(await eventually { connection.pendingRequests.contains { $0.request.type == .rest(.get, "states") } })
        answer(.rest(.get, "states"), with: Fixtures.restData("rest_states"))
        #expect(await eventually { service.camera("ha:camera.front_door") != nil })

        let channel = try #require(pushChannel)
        func push(_ event: HAData) { channel.handler(channel.cancellable, event) }
        func posted(_ match: (HomePadEvent) -> Bool) -> Bool { services.events.recent.contains { match($0.1) } }

        push(Fixtures.eventData("ws_event_push_show_camera"))
        #expect(service.cameraRequest == .show("ha:camera.front_door"))
        #expect(posted { if case .openApp("home") = $0 { true } else { false } })

        push(Fixtures.eventData("ws_event_push_message"))
        #expect(device.notification?.title == "Laundry")
        #expect(device.notification?.message == "The washer is done.")

        // Apps and faces by name, through the shell, so the recognition gate still applies.
        push(HAData(value: ["message": "homepad_open_app", "data": ["app": "Recipes"]]))
        #expect(posted { if case .openApp("recipes") = $0 { true } else { false } })
        push(HAData(value: ["message": "homepad_show_face", "data": ["face": "night"]]))
        #expect(posted { if case .showFace("faces.night") = $0 { true } else { false } })

        // Quiet Hours keep a spoken message to its banner.
        services.settings[CoreSettings.quietHoursEnabled] = true
        push(HAData(value: ["message": "homepad_speak", "data": ["text": "Dinner is ready"]]))
        #expect(device.notification?.message == "Dinner is ready")
        #expect(!posted { if case .custom(AssistantEventName.speak, _) = $0 { true } else { false } })
        services.settings[CoreSettings.quietHoursEnabled] = false
        push(HAData(value: ["message": "homepad_speak", "data": ["text": "Dinner is ready"]]))
        #expect(posted { if case .custom(AssistantEventName.speak, .string("Dinner is ready")) = $0 { true } else { false } })
    }

    @Test func turningOffMarksTheSensorsUnavailable() async throws {
        let device = makeDevice()
        await startActive(device)
        device.isEnabled = false
        #expect(await eventually { device.status == .off })
        #expect(await eventually { !transport.messages(ofType: "update_sensor_states").isEmpty })
        let states = transport.messages(ofType: "update_sensor_states").last?["data"]?.arrayValue ?? []
        #expect(states.count == MobileAppSensor.allCases.count)
        #expect(states.allSatisfy { $0["state"] == "unavailable" })
        #expect(connection.cancelledSubscriptions.contains { $0.type == .webSocket("mobile_app/push_notification_channel") })
        #expect(store.load() != nil)
    }

    @Test func removeDeletesItsOwnConfigEntry() async throws {
        let device = makeDevice()
        await startActive(device)
        let removal = Task { await device.removeFromHomeAssistant() }
        #expect(await eventually {
            connection.pendingRequests.contains { $0.request.data.isEmpty && $0.request.type == "config/device_registry/list" }
        })
        let request = try #require(connection.pendingRequests.last { $0.request.type == "config/device_registry/list" })
        request.completion(.success(Fixtures.resultData("ws_result_device_registry_mobile_app")))
        await removal.value

        #expect(transport.deletedEntries == ["entry_homepad"])
        #expect(device.registration == nil)
        #expect(store.load() == nil)
        #expect(!device.isEnabled)
        #expect(device.status == .off)
        #expect(device.removalMessage == "Removed Kitchen HomePad from Home Assistant.")
        #expect(MobileAppRegistration.configEntryID(deviceID: "missing",
                                                    deviceRegistry: JSONValue(haData: Fixtures.resultData("ws_result_device_registry_mobile_app"))) == nil)
    }
}
