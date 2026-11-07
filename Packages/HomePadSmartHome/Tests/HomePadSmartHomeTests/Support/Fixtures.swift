import Foundation
import HAKit
import HomePadCore
@testable import HomePadSmartHome

/// Loads the sample Home Assistant payloads in `Fixtures/`. They are captured in the
/// shape Home Assistant sends them: REST bodies, and WebSocket messages with their envelope.
enum Fixtures {
    static func url(_ name: String) -> URL {
        Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures")!
    }

    static func data(_ name: String) -> Data {
        try! Data(contentsOf: url(name))
    }

    /// The raw JSON object, as `JSONSerialization` (and so HAKit) produces it.
    static func object(_ name: String) -> Any {
        try! JSONSerialization.jsonObject(with: data(name))
    }

    /// A whole fixture as `JSONValue`, for `mobile_app` registration and webhook answers.
    static func json(_ name: String) -> JSONValue {
        JSONValue(foundation: object(name))
    }

    /// A REST body as HAKit hands it to a request completion.
    static func restData(_ name: String) -> HAData {
        HAData(value: object(name))
    }

    /// The `event` of a WebSocket event message, which HAKit passes to subscription handlers.
    static func eventData(_ name: String) -> HAData {
        HAData(value: (object(name) as! [String: Any])["event"])
    }

    /// The `result` of a successful WebSocket result message.
    static func resultData(_ name: String) -> HAData {
        HAData(value: (object(name) as! [String: Any])["result"])
    }

    static func states(_ name: String = "rest_states") throws -> [HAState] {
        try HAResponses.states(restData(name))
    }

    static func registry() -> HARegistry {
        HARegistry(
            areas: JSONValue(haData: resultData("ws_result_area_registry")),
            devices: JSONValue(haData: resultData("ws_result_device_registry")),
            entities: JSONValue(haData: resultData("ws_result_entity_registry"))
        )
    }

    /// The registries that go with `rest_states_trackers`: iCloud, Companion app,
    /// Life360 and router trackers.
    static func trackerRegistry() -> HARegistry {
        HARegistry(
            areas: [],
            devices: JSONValue(haData: resultData("ws_result_device_registry_trackers")),
            entities: JSONValue(haData: resultData("ws_result_entity_registry_trackers"))
        )
    }

    static func stateChange(_ name: String) throws -> HAStateChange {
        HAStateChange(event: try HAResponseEventStateChanged(data: eventData(name)))
    }

    static func context() -> HAStateMapper.Context {
        HAStateMapper.Context(registry: registry(), temperatureUnit: .celsius, baseURL: URL(string: "http://ha.test:8123"))
    }
}

/// Waits for asynchronous work on the main queue, such as HAKit delegate callbacks.
@MainActor
func eventually(timeout: Duration = .seconds(3), _ condition: () -> Bool) async -> Bool {
    let deadline = ContinuousClock.now + timeout
    while ContinuousClock.now < deadline {
        if condition() { return true }
        try? await Task.sleep(for: .milliseconds(10))
    }
    return condition()
}
