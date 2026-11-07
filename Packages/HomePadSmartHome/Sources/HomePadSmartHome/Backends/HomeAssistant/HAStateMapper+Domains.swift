import Foundation
import HomePadCore

extension HAStateMapper {
    /// Domain-specific kind, capabilities and state. Nil for domains HomePad does not show as tiles.
    static func mapDomain(_ state: HAState, context: Context) -> Mapped? {
        switch state.domain {
        case "light": return light(state)
        case "switch", "input_boolean": return Mapped(kind: .switchOutlet, capabilities: [.power], state: AccessoryState(isOn: state.state == "on"))
        case "fan": return fan(state)
        case "climate": return climate(state, unit: context.temperatureUnit)
        case "lock": return Mapped(kind: .lock, capabilities: [.lock], state: AccessoryState(lockState: lockState(state.state)))
        case "cover": return cover(state)
        case "media_player": return mediaPlayer(state, baseURL: context.baseURL)
        case "sensor": return sensor(state)
        case "binary_sensor": return binarySensor(state, context: context)
        case "alarm_control_panel": return alarm(state)
        case "vacuum": return vacuum(state)
        case "event": return event(state, context: context)
        default: return nil
        }
    }

    private static func light(_ state: HAState) -> Mapped {
        let modes = Set(state["supported_color_modes"]?.stringArray ?? [])
        var capabilities: Set<AccessoryCapability> = [.power]
        if (!modes.isEmpty && modes != ["onoff"]) || state["brightness"]?.doubleValue != nil {
            capabilities.insert(.brightness)
        }
        if modes.contains("color_temp") { capabilities.insert(.colorTemperature) }
        if !modes.isDisjoint(with: ["hs", "xy", "rgb", "rgbw", "rgbww"]) { capabilities.insert(.color) }
        var result = AccessoryState(isOn: state.state == "on")
        result.brightness = state["brightness"]?.doubleValue.map { $0 / 255 }
        result.colorTemperatureKelvin = state["color_temp_kelvin"]?.intValue
        if let hs = state["hs_color"]?.arrayValue, hs.count == 2 {
            result.hue = hs[0].doubleValue
            result.saturation = hs[1].doubleValue.map { $0 / 100 }
        }
        return Mapped(kind: .light, capabilities: capabilities, state: result)
    }

    private static func fan(_ state: HAState) -> Mapped {
        var capabilities: Set<AccessoryCapability> = [.power]
        if state.supports(HAFeature.fanSetSpeed) || state["percentage"]?.doubleValue != nil {
            capabilities.insert(.brightness)
        }
        // HomePad shows fan speed through the generic 0...1 level in `brightness`.
        let isOn = state.state == "on"
        let level = isOn ? state["percentage"]?.doubleValue.map { $0 / 100 } : nil
        return Mapped(kind: .fan, capabilities: capabilities, state: AccessoryState(isOn: isOn, brightness: level))
    }

    private static func climate(_ state: HAState, unit: TemperatureUnit) -> Mapped {
        var result = AccessoryState(isOn: state.state != "off")
        result.currentTemperature = state["current_temperature"]?.doubleValue
        if let target = state["temperature"]?.doubleValue {
            result.targetTemperature = target
        } else if let low = state["target_temp_low"]?.doubleValue, let high = state["target_temp_high"]?.doubleValue {
            result.targetTemperature = (low + high) / 2
        }
        result.temperatureUnit = unit
        result.hvacMode = HVACMode(homeAssistant: state.state)
        result.humidity = state["current_humidity"]?.doubleValue
        return Mapped(kind: .thermostat, capabilities: [.targetTemperature, .hvacMode], state: result)
    }

    static func lockState(_ value: String) -> LockState {
        switch value {
        case "locked": .locked
        case "unlocked", "open": .unlocked
        case "jammed": .jammed
        case "locking": .locking
        case "unlocking", "opening": .unlocking
        default: .unknown
        }
    }

    private static func cover(_ state: HAState) -> Mapped {
        let isDoor = ["garage", "gate", "door"].contains(state.deviceClass ?? "")
        var capabilities: Set<AccessoryCapability> = []
        let tiltsOnly = coverTiltsOnly(state)
        if state.supports(HAFeature.coverSetPosition) || tiltsOnly { capabilities.insert(.position) }
        var result = AccessoryState()
        result.doorState = DoorState(rawValue: state.state) ?? .unknown
        if let position = state["current_position"]?.doubleValue {
            result.position = position / 100
        } else if tiltsOnly, let tilt = state["current_tilt_position"]?.doubleValue {
            result.position = tilt / 100
        } else if state.state == "open" {
            result.position = 1
        } else if state.state == "closed" {
            result.position = 0
        }
        return Mapped(kind: isDoor ? .garageDoor : .cover, capabilities: capabilities, state: result)
    }

    /// Venetian blinds that only tilt their slats. How far the slats are open is
    /// their position, since that is how far open they look.
    static func coverTiltsOnly(_ state: HAState) -> Bool {
        !state.supports(HAFeature.coverSetPosition) && state.supports(HAFeature.coverSetTiltPosition)
    }

    private static func mediaPlayer(_ state: HAState, baseURL: URL?) -> Mapped {
        var capabilities: Set<AccessoryCapability> = [.power, .playback]
        if state.supports(HAFeature.mediaVolumeSet) || state["volume_level"] != nil { capabilities.insert(.volume) }
        var result = AccessoryState(isOn: !["off", "standby", "unavailable"].contains(state.state))
        result.isPlaying = state.state == "playing"
        result.isActive = result.isPlaying
        result.mediaTitle = state["media_title"]?.stringValue
        result.mediaArtist = state["media_artist"]?.stringValue ?? state["media_album_artist"]?.stringValue
        result.volume = state["volume_level"]?.doubleValue
        result.mediaPosition = state["media_position"]?.doubleValue
        result.mediaDuration = state["media_duration"]?.doubleValue
        result.mediaPositionUpdatedAt = state["media_position_updated_at"]?.stringValue.flatMap(HAResponses.parseDate)
        result.mediaArtworkURL = state["entity_picture"]?.stringValue.flatMap { artworkURL($0, baseURL: baseURL) }
        result.mediaAlbum = state["media_album_name"]?.stringValue
        let members = state["group_members"]?.stringArray ?? []
        result.mediaGroupMemberIDs = members.isEmpty ? nil : members.map { BackendID.make(.homeAssistant, $0) }
        return Mapped(kind: .mediaPlayer, capabilities: capabilities, state: result)
    }

    /// `entity_picture` is usually a path on the HA server (`/api/media_player_proxy/...`).
    static func artworkURL(_ picture: String, baseURL: URL?) -> URL? {
        if let absolute = URL(string: picture), absolute.scheme != nil { return absolute }
        guard let baseURL else { return nil }
        return URL(string: picture, relativeTo: baseURL)?.absoluteURL
    }

    /// Numeric sensors only. Text sensors have no tile that makes sense.
    private static func sensor(_ state: HAState) -> Mapped? {
        let value = state.numericState
        guard value != nil || state.isUnavailable || state.isUnknown else { return nil }
        var result = AccessoryState(sensorValue: value, sensorUnit: state["unit_of_measurement"]?.stringValue)
        switch state.deviceClass {
        case "temperature": result.currentTemperature = value
        case "humidity": result.humidity = value
        case "battery": result.batteryLevel = value.map { $0 / 100 }
        default: break
        }
        return Mapped(kind: .sensor, capabilities: [], state: result)
    }

    private static func binarySensor(_ state: HAState, context: Context) -> Mapped {
        let isOn = state.state == "on"
        if HADoorbellDetector.isDoorbellEntity(state, configuredTriggerID: context.doorbellTriggerID) {
            return Mapped(kind: .doorbell, capabilities: [], state: AccessoryState(isActive: isOn))
        }
        var result = AccessoryState(isActive: isOn)
        if ["door", "window", "garage_door", "opening"].contains(state.deviceClass ?? "") {
            result.doorState = isOn ? .open : .closed
        }
        return Mapped(kind: .sensor, capabilities: [], state: result)
    }

    private static func alarm(_ state: HAState) -> Mapped {
        let armed = state.state.hasPrefix("armed") || ["triggered", "arming", "pending"].contains(state.state)
        // `isActive` means "triggered" for security systems.
        let result = AccessoryState(isOn: armed, isActive: state.state == "triggered")
        return Mapped(kind: .securitySystem, capabilities: [.power], state: result)
    }

    private static func vacuum(_ state: HAState) -> Mapped {
        var result = AccessoryState(isOn: state.state == "cleaning")
        result.batteryLevel = state["battery_level"]?.doubleValue.map { $0 / 100 }
        return Mapped(kind: .vacuum, capabilities: [.power], state: result)
    }

    /// Event entities only appear when they are doorbells.
    private static func event(_ state: HAState, context: Context) -> Mapped? {
        guard HADoorbellDetector.isDoorbellEntity(state, configuredTriggerID: context.doorbellTriggerID) else { return nil }
        return Mapped(kind: .doorbell, capabilities: [], state: AccessoryState(isActive: false))
    }
}
