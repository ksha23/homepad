import Foundation
import HAKit
import HomePadCore
import Testing
@testable import HomePadSmartHome

/// WebSocket and REST payloads as Home Assistant sends them, decoded through HAKit's
/// types and HomePad's adapters.
@Suite("Home Assistant message decoding")
struct HAWebSocketDecodingTests {
    @Test func stateChangedEvent() throws {
        let change = try Fixtures.stateChange("ws_event_light_off")
        #expect(change.entityID == "light.kitchen")
        #expect(change.oldState?.state == "on")
        #expect(change.oldState?["brightness"]?.doubleValue == 178)
        #expect(change.newState?.state == "off")
        #expect(change.newState?["brightness"] == .null)
        let newState = try #require(change.newState)
        let mapped = try #require(HAStateMapper.accessory(from: newState, context: Fixtures.context()))
        #expect(mapped.state.isOn == false)
        #expect(mapped.state.brightness == nil)
    }

    @Test func removedEntityHasNoNewState() throws {
        let change = try Fixtures.stateChange("ws_event_entity_removed")
        #expect(change.entityID == "switch.coffee")
        #expect(change.newState == nil)
        #expect(change.oldState?.state == "off")
    }

    @Test func attributesKeepTheirTypes() throws {
        let states = try Fixtures.states()
        let alarm = try #require(states.first { $0.entityID == "alarm_control_panel.home" })
        #expect(alarm["code_arm_required"] == .bool(false), "booleans stay booleans, not 0")
        let light = try #require(states.first { $0.entityID == "light.kitchen" })
        #expect(light["supported_color_modes"]?.stringArray == ["color_temp", "hs"])
        #expect(light["hs_color"] == [30, 40])
        #expect(light.supportedFeatures == 40)
        #expect(light.lastChanged.timeIntervalSince1970 > 1_790_000_000)
    }

    @Test func doorbellEventRings() throws {
        let change = try Fixtures.stateChange("ws_event_doorbell_ring")
        #expect(HADoorbellDetector.isRing(change, configuredTriggerID: nil))
    }

    @Test func doorbellRestoredAfterRestartDoesNotRing() throws {
        let change = try Fixtures.stateChange("ws_event_doorbell_restored")
        #expect(!HADoorbellDetector.isRing(change, configuredTriggerID: nil))
    }

    @Test func doorbellBinarySensorRingsOnTurningOn() throws {
        let change = try Fixtures.stateChange("ws_event_side_doorbell_on")
        #expect(HADoorbellDetector.isRing(change, configuredTriggerID: nil))
        let reversed = HAStateChange(entityID: change.entityID, oldState: change.newState, newState: change.oldState)
        #expect(!HADoorbellDetector.isRing(reversed, configuredTriggerID: nil))
    }

    @Test func ordinaryChangesAreNotRings() throws {
        #expect(!HADoorbellDetector.isRing(try Fixtures.stateChange("ws_event_light_off"), configuredTriggerID: nil))
        #expect(!HADoorbellDetector.isRing(try Fixtures.stateChange("ws_event_lock_unlocked"), configuredTriggerID: nil))
    }

    @Test func configuredTriggerRings() {
        let off = HAState(entityID: "input_boolean.bell", state: "off")
        let on = HAState(entityID: "input_boolean.bell", state: "on")
        let change = HAStateChange(entityID: "input_boolean.bell", oldState: off, newState: on)
        #expect(!HADoorbellDetector.isRing(change, configuredTriggerID: nil))
        #expect(HADoorbellDetector.isRing(change, configuredTriggerID: "input_boolean.bell"))
    }

    @Test func doorbellFindsItsCamera() {
        let registry = Fixtures.registry()
        let cameras = ["camera.backyard", "camera.front_door"]
        #expect(HADoorbellDetector.cameraEntityID(forDoorbell: "event.front_doorbell", cameraEntityIDs: cameras, registry: registry) == "camera.front_door")
        #expect(HADoorbellDetector.cameraEntityID(forDoorbell: "binary_sensor.side_doorbell", cameraEntityIDs: cameras, registry: registry) == nil,
                "the side bell's garage has no camera")
    }

    @Test func registries() {
        let registry = Fixtures.registry()
        #expect(registry.areas.count == 4)
        #expect(registry.devices["dev_porch"]?.name == "Porch", "name_by_user wins")
        #expect(registry.roomName(for: "light.kitchen") == "Kitchen")
        #expect(registry.roomName(for: "event.front_doorbell") == "Entryway")
        #expect(registry.roomName(for: "camera.backyard") == nil)
        #expect(registry.isHidden("light.hidden_strip"))
        #expect(registry.isHidden("sensor.cpu_temp"))
        #expect(registry.isHidden("switch.disabled_plug"))
        #expect(!registry.isHidden("light.kitchen"))
        #expect(!registry.isHidden("light.not_in_registry"))
    }

    @Test func cameraStreamResult() {
        let url = HAResponses.streamURL(JSONValue(haData: Fixtures.resultData("ws_result_camera_stream")), baseURL: URL(string: "http://ha.test:8123")!)
        #expect(url?.absoluteString == "http://ha.test:8123/api/hls/7f3a9c/master_playlist.m3u8")
    }

    @Test func errorResultCarriesCodeAndMessage() throws {
        let message = Fixtures.object("ws_result_error") as! [String: Any]
        #expect(message["success"] as? Bool == false)
        let error = HAError.external(.init(code: "service_validation_error", message: "Entity lock.garage is not available"))
        #expect(error.localizedDescription == "Entity lock.garage is not available")
    }

    @Test func serverConfig() {
        let config = HAServerConfig(json: JSONValue(haData: Fixtures.restData("rest_config")))
        #expect(config.locationName == "Maple Street")
        #expect(config.version == "2026.10.2")
        #expect(config.temperatureUnit == .fahrenheit)
        #expect(HAServerConfig(json: ["unit_system": ["temperature": "°C"]]).temperatureUnit == .celsius)
    }

    @Test func history() {
        let samples = HAResponses.history(JSONValue(haData: Fixtures.restData("rest_history")))
        #expect(samples.map(\.value) == [20.9, 21.2, 21.6], "unavailable points are skipped")
        #expect(samples.first?.date == HAResponses.parseDate("2026-10-19T14:00:00+00:00"))
        #expect(HAResponses.parseDate("2026-10-20T14:03:11.123456+00:00") != nil)
    }

    @Test func historyRequestShape() throws {
        let request = HARequests.history("sensor.living_temperature", since: Date(timeIntervalSince1970: 1_790_000_000))
        guard case .rest(let method, let path) = request.type else {
            Issue.record("history must be a REST request")
            return
        }
        #expect(method == .get)
        #expect(path.hasPrefix("history/period/2026-"))
        #expect(request.queryItems.map(\.name) == ["filter_entity_id", "minimal_response", "no_attributes"])
    }

    @Test func dashboardCatalog() {
        let dashboards = HADashboardCatalog.dashboards(from: JSONValue(haData: Fixtures.resultData("ws_result_dashboards")))
        #expect(dashboards.map(\.title) == ["Overview", "Tablet"])
        #expect(dashboards.map(\.urlPath) == [nil, "dashboard-tablet"])
        let views = HADashboardCatalog.views(from: JSONValue(haData: Fixtures.resultData("ws_result_lovelace_config")),
                                             urlPath: "dashboard-tablet", dashboardTitle: "Tablet")
        #expect(views.map(\.path) == ["/dashboard-tablet/kitchen", "/dashboard-tablet/1"])
        #expect(views.map(\.title) == ["Tablet, Kitchen", "Tablet, Cameras"])
        #expect(HADashboardCatalog.views(from: .null, urlPath: nil, dashboardTitle: "Overview").map(\.path) == ["/lovelace/0"])
    }
}
