import Foundation
import HomePadCore

/// Turns Home Assistant device trackers and zones into `TrackedDevice` and
/// `HomeZone` for Find My. Pure and synchronous, like `HAStateMapper`.
///
/// Only trackers with GPS count: the iCloud integration, the Companion app and
/// others such as Life360. Router and Bluetooth trackers say only home or away
/// and would list every television on the Wi-Fi, so they are left out.
enum HATrackerMapper {
    struct Output: Equatable {
        var devices: [TrackedDevice] = []
        var zones: [HomeZone] = []
    }

    static func map(_ states: [HAState], registry: HARegistry) -> Output {
        let owners = ownerNames(from: states)
        let sensors = DeviceSensors(states: states, registry: registry)
        var output = Output()
        for state in states {
            switch state.domain {
            case "device_tracker":
                guard !registry.isHidden(state.entityID),
                      let device = device(from: state, registry: registry, owners: owners, sensors: sensors) else { continue }
                output.devices.append(device)
            case "zone":
                if let zone = zone(from: state) { output.zones.append(zone) }
            default:
                continue
            }
        }
        output.devices.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        output.zones.sort { ($0.isHome ? 0 : 1, $0.name) < ($1.isHome ? 0 : 1, $1.name) }
        return output
    }

    /// One GPS tracker, or nil for trackers without GPS.
    static func device(from state: HAState, registry: HARegistry, owners: [String: String] = [:],
                       sensors: DeviceSensors = DeviceSensors()) -> TrackedDevice? {
        let latitude = state["latitude"]?.doubleValue
        let longitude = state["longitude"]?.doubleValue
        let sourceType = state["source_type"]?.stringValue
        guard sourceType == "gps" || (latitude != nil && longitude != nil) else { return nil }
        let platform = registry.platform(of: state.entityID)
        let deviceID = registry.deviceID(for: state.entityID)
        // iCloud reports `battery`, the Companion app and older integrations `battery_level`.
        var battery = (state["battery"] ?? state["battery_level"])?.doubleValue.map { $0 / 100 }
        var charging = state["battery_status"]?.stringValue.flatMap(isChargingStatus)
        if let deviceID {
            battery = battery ?? sensors.batteryLevel[deviceID]
            charging = charging ?? sensors.isCharging[deviceID]
        }
        let source = source(platform: platform, state: state)
        // iCloud's `device_name` attribute is the model ("iPhone 15 Pro"), not the device's name.
        let model = registry.deviceModel(for: state.entityID) ?? (source == .iCloud ? state["device_name"]?.stringValue : nil)
        return TrackedDevice(
            id: BackendID.make(.homeAssistant, state.entityID),
            name: HAStateMapper.displayName(of: state, registry: registry),
            source: source,
            integration: platform,
            model: model,
            place: place(for: state.state),
            latitude: latitude,
            longitude: longitude,
            accuracy: state["gps_accuracy"]?.doubleValue,
            batteryLevel: battery.map { min(max($0, 0), 1) },
            isCharging: charging,
            lastUpdated: state.lastUpdated,
            ownerName: owners[state.entityID] ?? state["owner_fullname"]?.stringValue
        )
    }

    /// A zone with its center and radius. Nil when it has no coordinates.
    static func zone(from state: HAState) -> HomeZone? {
        guard let latitude = state["latitude"]?.doubleValue, let longitude = state["longitude"]?.doubleValue else { return nil }
        return HomeZone(
            id: BackendID.make(.homeAssistant, state.entityID),
            name: state.friendlyName ?? HAStateMapper.humanized(state.entityID),
            latitude: latitude,
            longitude: longitude,
            radius: state["radius"]?.doubleValue ?? 100,
            isHome: state.entityID == "zone.home"
        )
    }

    /// A tracker's state is `home`, `not_home` or the name of the zone it is in.
    static func place(for state: String) -> TrackedDevice.Place {
        switch state {
        case "home": .home
        case "not_home": .away
        case "unknown", "unavailable", "": .unknown
        default: .zone(state)
        }
    }

    static func source(platform: String?, state: HAState) -> TrackedDevice.Source {
        switch platform {
        case "icloud": return .iCloud
        case "mobile_app": return .companionApp
        case .some: return .other
        case nil:
            // Before the entity registry loads, the iCloud integration's own attributes give it away.
            return state["device_status"] != nil && state["account_fetch_interval"] != nil ? .iCloud : .other
        }
    }

    /// Person names by the tracker entity IDs each `person` lists in `device_trackers`.
    static func ownerNames(from states: [HAState]) -> [String: String] {
        var owners: [String: String] = [:]
        for person in states where person.domain == "person" {
            let name = person.friendlyName ?? HAStateMapper.humanized(person.entityID)
            for tracker in person["device_trackers"]?.stringArray ?? [] where owners[tracker] == nil {
                owners[tracker] = name
            }
        }
        return owners
    }

    /// iCloud's `battery_status` and the Companion app's battery state sensor.
    /// Full counts as charging, since the device is on its charger.
    static func isChargingStatus(_ status: String) -> Bool? {
        switch status.lowercased().replacingOccurrences(of: " ", with: "") {
        case "charging", "charged", "full": true
        case "notcharging", "unplugged", "discharging": false
        default: nil
        }
    }
}

extension HATrackerMapper {
    /// Battery readings from sensors on the same device as a tracker, as the
    /// Companion app reports them (`sensor.<device>_battery_level` and `_battery_state`).
    struct DeviceSensors {
        var batteryLevel: [String: Double] = [:]
        var isCharging: [String: Bool] = [:]

        init() {}

        init(states: [HAState], registry: HARegistry) {
            for state in states where state.domain == "sensor" {
                guard let deviceID = registry.deviceID(for: state.entityID) else { continue }
                if state.deviceClass == "battery", let value = state.numericState {
                    batteryLevel[deviceID] = value / 100
                } else if state.entityID.hasSuffix("_battery_state"), let charging = HATrackerMapper.isChargingStatus(state.state) {
                    isCharging[deviceID] = charging
                }
            }
        }
    }
}
