import Foundation

/// Recognizes doorbell presses in Home Assistant state changes:
/// doorbell `event` entities, `binary_sensor`s with device class `doorbell`,
/// and an extra entity the person picked in Settings.
enum HADoorbellDetector {
    static func isDoorbellEntity(_ state: HAState, configuredTriggerID: String?) -> Bool {
        if state.entityID == configuredTriggerID { return true }
        switch state.domain {
        case "event", "binary_sensor": return state.deviceClass == "doorbell"
        default: return false
        }
    }

    /// True when this change is a fresh press, not a restore after a restart.
    static func isRing(_ change: HAStateChange, configuredTriggerID: String?) -> Bool {
        guard let new = change.newState, let old = change.oldState,
              isDoorbellEntity(new, configuredTriggerID: configuredTriggerID),
              !old.isUnavailable, !new.isUnavailable, !new.isUnknown,
              old.state != new.state else { return false }
        switch new.domain {
        case "event":
            // The state is the timestamp of the last event, so any new value is a press.
            return true
        case "binary_sensor", "input_boolean", "switch":
            return old.state == "off" && new.state == "on"
        default:
            // A sensor or button picked as the doorbell: any change away from a resting state.
            return !["off", "idle", "clear"].contains(new.state)
        }
    }

    /// The camera that belongs to a doorbell entity: same device first, then same area.
    static func cameraEntityID(forDoorbell entityID: String, cameraEntityIDs: [String], registry: HARegistry) -> String? {
        let cameras = cameraEntityIDs.sorted()
        if let device = registry.deviceID(for: entityID),
           let match = cameras.first(where: { registry.deviceID(for: $0) == device }) {
            return match
        }
        if let area = registry.areaID(for: entityID),
           let match = cameras.first(where: { registry.areaID(for: $0) == area }) {
            return match
        }
        return nil
    }
}
