import HomePadCore

/// Home Assistant's area, device and entity registries, used for room names,
/// grouping a doorbell with its camera, and hiding entities the person hid.
struct HARegistry: Equatable, Sendable {
    struct Area: Equatable, Sendable {
        var id: String
        var name: String
    }

    struct Device: Equatable, Sendable {
        var id: String
        var name: String?
        var areaID: String?
        /// The model the integration reports, for example "HomePod mini".
        var model: String?
        /// The name the integration registered, before any rename in Home
        /// Assistant. The Companion app's notify action is named after it.
        var registeredName: String?
    }

    struct Entity: Equatable, Sendable {
        var entityID: String
        var deviceID: String?
        var areaID: String?
        var name: String?
        /// The integration that created the entity, for example `music_assistant` or `sonos`.
        var platform: String?
        /// The integration instance it belongs to, such as one iCloud account.
        var configEntryID: String?
        /// Hidden or disabled by the person or an integration, or a config or diagnostic entity.
        var isHidden: Bool
    }

    /// Events that mean a registry changed and should be fetched again.
    static let updateEventTypes = ["area_registry_updated", "device_registry_updated", "entity_registry_updated"]

    var areas: [String: Area] = [:]
    var devices: [String: Device] = [:]
    var entities: [String: Entity] = [:]

    init() {}

    /// Builds the registry from the results of `config/area_registry/list`,
    /// `config/device_registry/list` and `config/entity_registry/list`.
    init(areas: JSONValue, devices: JSONValue, entities: JSONValue) {
        for item in areas.arrayValue ?? [] {
            guard let id = item["area_id"]?.stringValue else { continue }
            self.areas[id] = Area(id: id, name: item["name"]?.stringValue ?? id)
        }
        for item in devices.arrayValue ?? [] {
            guard let id = item["id"]?.stringValue else { continue }
            let name = item["name_by_user"]?.stringValue ?? item["name"]?.stringValue
            self.devices[id] = Device(id: id, name: name, areaID: item["area_id"]?.stringValue, model: item["model"]?.stringValue,
                                      registeredName: item["name"]?.stringValue)
        }
        for item in entities.arrayValue ?? [] {
            guard let id = item["entity_id"]?.stringValue else { continue }
            let hidden = item["hidden_by"]?.stringValue != nil
                || item["disabled_by"]?.stringValue != nil
                || item["entity_category"]?.stringValue != nil
            self.entities[id] = Entity(
                entityID: id, deviceID: item["device_id"]?.stringValue, areaID: item["area_id"]?.stringValue,
                name: item["name"]?.stringValue, platform: item["platform"]?.stringValue,
                configEntryID: item["config_entry_id"]?.stringValue, isHidden: hidden
            )
        }
    }

    func deviceID(for entityID: String) -> String? {
        entities[entityID]?.deviceID
    }

    /// The entity's own area, or its device's area.
    func areaID(for entityID: String) -> String? {
        guard let entity = entities[entityID] else { return nil }
        return entity.areaID ?? entity.deviceID.flatMap { devices[$0]?.areaID }
    }

    func roomName(for entityID: String) -> String? {
        areaID(for: entityID).flatMap { areas[$0]?.name }
    }

    /// The model of the entity's device.
    func deviceModel(for entityID: String) -> String? {
        deviceID(for: entityID).flatMap { devices[$0]?.model }
    }

    func platform(of entityID: String) -> String? {
        entities[entityID]?.platform
    }

    func isHidden(_ entityID: String) -> Bool {
        entities[entityID]?.isHidden ?? false
    }
}
