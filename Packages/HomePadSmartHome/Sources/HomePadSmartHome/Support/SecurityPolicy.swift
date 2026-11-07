import HomePadCore

/// Decides which commands open up the home: unlocking a lock, opening a garage door
/// or gate, and disarming a security system. A guest (nobody recognized) may only run
/// these after an explicit confirmation on screen. Raw service calls and assistant
/// requests have no confirmation step, so they need a recognized member.
enum SecurityPolicy {
    static func isSensitive(_ command: AccessoryCommand, on accessory: HomeAccessory) -> Bool {
        let state = accessory.state
        switch accessory.kind {
        case .lock:
            switch command {
            case .unlock, .open: return true
            case .toggle: return state.lockState != .unlocked
            default: return false
            }
        case .garageDoor:
            switch command {
            case .open: return true
            case .setPower(let on): return on
            case .setPosition(let value): return value > (state.position ?? 0)
            case .toggle: return !isOpen(state)
            default: return false
            }
        case .securitySystem:
            switch command {
            case .unlock: return true
            case .setPower(let on): return !on
            case .toggle: return state.isOn ?? true
            default: return false
            }
        default:
            return false
        }
    }

    /// Raw Home Assistant calls that unlock, open or disarm. `kindOf` looks up the
    /// accessory kind for an entity so covers are only sensitive when they are doors.
    static func isSensitiveServiceCall(
        domain: String, service: String, entityIDs: [String], kindOf: (String) -> AccessoryKind?
    ) -> Bool {
        switch (domain, service) {
        case ("lock", "unlock"), ("lock", "open"), ("alarm_control_panel", "alarm_disarm"):
            return true
        case ("cover", "open_cover"), ("cover", "toggle"), ("cover", "set_cover_position"):
            return entityIDs.isEmpty || entityIDs.contains { kindOf($0) == .garageDoor }
        default:
            return false
        }
    }

    /// Raw Home Assistant commands other modules may send through `sendCommand`:
    /// action calls (checked like `callService`) and commands that only read.
    static let allowedRawCommands: Set<String> = [
        SmartHomeCommandType.callService, SmartHomeCommandType.configEntries, SmartHomeCommandType.browseMedia,
        "get_states", "get_services", "get_config",
        "config/area_registry/list", "config/device_registry/list", "config/entity_registry/list",
    ]

    /// The entity IDs an action call targets, from `target` and from `entity_id` in its data.
    static func targetEntityIDs(serviceData: JSONValue?, target: JSONValue?) -> [String] {
        [serviceData?["entity_id"], target?["entity_id"]].flatMap { value -> [String] in
            switch value {
            case .string(let id): [id]
            case .array(let ids): ids.compactMap(\.stringValue)
            default: []
            }
        }
    }

    /// The word for the confirmation button, such as "Unlock" or "Open".
    static func confirmationVerb(for kind: AccessoryKind) -> String {
        switch kind {
        case .lock: "Unlock"
        case .securitySystem: "Disarm"
        default: "Open"
        }
    }

    private static func isOpen(_ state: AccessoryState) -> Bool {
        if let door = state.doorState { return door == .open || door == .opening }
        return (state.position ?? 0) > 0.01
    }
}
