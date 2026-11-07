import Foundation
import HomePadCore

/// The sensors a HomePad gives Home Assistant: only what HomePad already knows
/// and shows. Faces, face data, photos and sound never leave the iPad.
///
/// Home Assistant names each entity after the device and the sensor, for
/// example `binary_sensor.kitchen_homepad_someone_present`.
enum MobileAppSensor: String, CaseIterable, Sendable {
    case presence
    case proximity
    case recognized
    case roomLight = "room_light"
    case screen
    case face
    case app
    case brightness
    case battery
    case charging

    /// Unique within this device's registration. Never change one: Home
    /// Assistant would see a new sensor.
    var uniqueID: String { rawValue }

    var name: String {
        switch self {
        case .presence: "Someone Present"
        case .proximity: "Proximity"
        case .recognized: "Recognized"
        case .roomLight: "Room Light"
        case .screen: "Screen"
        case .face: "Face"
        case .app: "App"
        case .brightness: "Brightness"
        case .battery: "Battery"
        case .charging: "Charging"
        }
    }

    var isBinary: Bool { self == .presence || self == .charging }

    var type: String { isBinary ? "binary_sensor" : "sensor" }

    var deviceClass: String? {
        switch self {
        case .presence: "occupancy"
        case .roomLight: "illuminance"
        case .battery: "battery"
        case .charging: "battery_charging"
        case .proximity, .recognized, .screen, .face, .app, .brightness: nil
        }
    }

    var unit: String? {
        switch self {
        case .roomLight: "lx"
        case .brightness, .battery: "%"
        default: nil
        }
    }

    /// Numbers that move are measurements, so Home Assistant keeps statistics.
    var stateClass: String? {
        switch self {
        case .roomLight, .brightness, .battery: "measurement"
        default: nil
        }
    }

    /// The iPad's own health goes under Diagnostic in Home Assistant.
    var entityCategory: String? {
        switch self {
        case .battery, .charging: "diagnostic"
        default: nil
        }
    }
}

/// One sensor's value, as Home Assistant gets it.
struct MobileAppSensorState: Equatable, Sendable {
    var sensor: MobileAppSensor
    /// A boolean, a number, a string, or "unavailable" when HomePad cannot tell.
    var state: JSONValue
    var icon: String
    var attributes: [String: JSONValue] = [:]

    static let unavailable: JSONValue = "unavailable"

    /// The `register_sensor` message. Registering a sensor that exists updates
    /// it, and values left out are reset, so the state, icon and attributes go too.
    var registerMessage: JSONValue {
        var data: [String: JSONValue] = [
            "type": .string(sensor.type),
            "unique_id": .string(sensor.uniqueID),
            "name": .string(sensor.name),
            "state": state,
            "icon": .string(icon),
            "attributes": .object(attributes),
        ]
        if let deviceClass = sensor.deviceClass { data["device_class"] = .string(deviceClass) }
        if let unit = sensor.unit { data["unit_of_measurement"] = .string(unit) }
        if let stateClass = sensor.stateClass { data["state_class"] = .string(stateClass) }
        if let category = sensor.entityCategory { data["entity_category"] = .string(category) }
        return ["type": "register_sensor", "data": .object(data)]
    }

    /// This sensor's entry in `update_sensor_states`. Attributes replace the old
    /// ones and a missing icon goes back to the default, so both are sent.
    var update: JSONValue {
        [
            "type": .string(sensor.type),
            "unique_id": .string(sensor.uniqueID),
            "state": state,
            "icon": .string(icon),
            "attributes": .object(attributes),
        ]
    }

    /// True when Home Assistant should hear about this value after `old`. Room
    /// light moves a little all the time, so it counts when it crosses into
    /// another level or moves by a fifth.
    func differs(from old: MobileAppSensorState) -> Bool {
        guard sensor == .roomLight, attributes == old.attributes, icon == old.icon,
              let new = state.doubleValue, let previous = old.state.doubleValue else {
            return self != old
        }
        return abs(new - previous) >= max(1, previous * 0.2)
    }
}

extension MobileAppSensorState {
    /// The `update_sensor_states` message for several sensors at once.
    static func updateMessage(_ states: [MobileAppSensorState]) -> JSONValue {
        ["type": "update_sensor_states", "data": .array(states.map(\.update))]
    }

    /// Sensors Home Assistant answered `not_registered` for, so they are
    /// registered again. Other failures are left for the next change.
    static func unregistered(in response: JSONValue) -> [MobileAppSensor] {
        guard let results = response.objectValue else { return [] }
        return MobileAppSensor.allCases.filter { sensor in
            results[sensor.uniqueID]?["error"]?["code"]?.stringValue == "not_registered"
        }
    }

    /// Sensors Home Assistant took. A sensor turned off in Home Assistant counts.
    static func accepted(in response: JSONValue) -> Set<MobileAppSensor> {
        guard let results = response.objectValue else { return [] }
        return Set(MobileAppSensor.allCases.filter { results[$0.uniqueID]?["success"]?.boolValue == true })
    }
}
