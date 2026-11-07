import HomePadCore
import HomePadUI
import SwiftUI

/// How an accessory looks on tiles and in detail screens: a state-aware symbol,
/// a short status, whether it reads as "on", and what one tap does.
enum AccessoryPresentation {
    /// A group's status: how many it holds and their shared state ("3 Lights · On,
    /// 70%"), or how many are on when they differ ("2 of 3 On").
    static func groupStatus(for group: HomeAccessory, members: [HomeAccessory]) -> String {
        let powered = members.filter(\.state.isReachable).compactMap(\.state.isOn)
        let onCount = powered.filter { $0 }.count
        if onCount > 0, onCount < powered.count { return "\(onCount) of \(members.count) On" }
        return "\(memberCount(members.count, kind: group.kind)) · \(status(for: group))"
    }

    /// "3 Lights", "2 Fans", "4 Accessories".
    static func memberCount(_ count: Int, kind: AccessoryKind) -> String {
        let noun: (String, String) = switch kind {
        case .light: ("Light", "Lights")
        case .fan: ("Fan", "Fans")
        case .switchOutlet: ("Outlet", "Outlets")
        case .lock: ("Lock", "Locks")
        case .cover: ("Blind", "Blinds")
        case .mediaPlayer: ("Speaker", "Speakers")
        default: ("Accessory", "Accessories")
        }
        return "\(count) \(count == 1 ? noun.0 : noun.1)"
    }

    static func symbol(for accessory: HomeAccessory) -> String {
        let state = accessory.state
        switch accessory.kind {
        case .light: return state.isOn == true ? "lightbulb.fill" : "lightbulb"
        case .lock: return state.lockState == .unlocked ? "lock.open.fill" : "lock.fill"
        case .garageDoor: return isOpen(state) ? "door.garage.open" : "door.garage.closed"
        case .cover: return isOpen(state) ? "blinds.horizontal.open" : "blinds.horizontal.closed"
        case .securitySystem: return state.isOn == true ? "shield.lefthalf.filled" : "shield.slash"
        case .mediaPlayer: return state.isPlaying == true ? "hifispeaker.fill" : "hifispeaker"
        case .sensor: return sensorSymbol(for: accessory)
        default: return accessory.kind.systemImage
        }
    }

    static func status(for accessory: HomeAccessory) -> String {
        let state = accessory.state
        guard state.isReachable else { return "No Response" }
        switch accessory.kind {
        case .securitySystem:
            if state.isActive == true { return "Triggered" }
            return state.isOn == true ? "Armed" : "Disarmed"
        case .vacuum:
            return state.isOn == true ? "Cleaning" : "Docked"
        case .doorbell, .sensor:
            return reading(for: accessory).value
        case .mediaPlayer:
            guard state.isOn == true else { return "Off" }
            if state.isPlaying == true, let title = state.mediaTitle { return title }
            return "Paused"
        case .thermostat:
            guard let mode = state.hvacMode, mode != .off, let target = state.targetTemperature else {
                return state.currentTemperature.map { "\(Int($0.rounded()))°, Off" } ?? "Off"
            }
            return "\(modeVerb(mode)) to \(Int(target.rounded()))°"
        default:
            break
        }
        return accessory.statusText
    }

    /// Whether the tile should light up, like Apple Home's bright "on" tiles.
    static func isActive(_ accessory: HomeAccessory) -> Bool {
        let state = accessory.state
        guard state.isReachable else { return false }
        switch accessory.kind {
        case .lock: return state.lockState == .unlocked
        case .garageDoor, .cover: return isOpen(state)
        case .thermostat: return state.hvacMode.map { $0 != .off } ?? false
        case .sensor, .doorbell: return state.isActive == true
        default: return state.isOn == true
        }
    }

    /// What tapping the tile's icon does. Nil opens the detail controls instead.
    static func primaryCommand(for accessory: HomeAccessory) -> AccessoryCommand? {
        switch accessory.kind {
        case .light, .switchOutlet, .fan, .airPurifier: return .toggle
        case .lock: return accessory.state.lockState == .locked ? .unlock : .lock
        case .garageDoor, .cover: return isOpen(accessory.state) ? .close : .open
        case .mediaPlayer: return accessory.state.isPlaying == true ? .pause : .play
        default: return nil
        }
    }

    /// The level that pressing and dragging on a tile sets, from 0 to 1: brightness
    /// for a dimmable light, speed for a fan, how far open for a blind. Nil when the
    /// accessory has no level to set.
    static func level(of accessory: HomeAccessory) -> Double? {
        let state = accessory.state
        switch accessory.kind {
        case .light, .fan:
            guard accessory.capabilities.contains(.brightness) else { return nil }
            return state.isOn == true ? state.brightness ?? 1 : 0
        case .cover:
            guard accessory.capabilities.contains(.position) else { return nil }
            return state.position ?? (isOpen(state) ? 1 : 0)
        default:
            return nil
        }
    }

    /// The command that sets `level` (0 to 1) on an accessory that has one.
    static func levelCommand(_ level: Double, for accessory: HomeAccessory) -> AccessoryCommand {
        let level = min(max(level, 0), 1)
        return accessory.kind == .cover ? .setPosition(level) : .setBrightness(level)
    }

    /// How much of a tile the accessory's color covers (Core's `tileFill`),
    /// with the tile on while the accessory is active.
    static func fillFraction(of accessory: HomeAccessory) -> Double {
        accessory.tileFill(isOn: isActive(accessory))
    }

    /// "Brightness", "Speed" or "Open", for the level's accessibility label.
    static func levelName(for accessory: HomeAccessory) -> String {
        switch accessory.kind {
        case .fan: "Speed"
        case .cover: "Open"
        default: "Brightness"
        }
    }

    static func modeVerb(_ mode: HVACMode) -> String {
        switch mode {
        case .heat: "Heating"
        case .cool: "Cooling"
        case .auto: "Keeping"
        case .fanOnly: "Fan"
        case .dry: "Drying"
        case .off: "Off"
        }
    }

    static func isOpen(_ state: AccessoryState) -> Bool {
        if let door = state.doorState, door != .unknown { return door == .open || door == .opening }
        return (state.position ?? 0) > 0.01
    }
}
