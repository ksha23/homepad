import Foundation
import HomePadCore

/// Decides which actions need a spoken or tapped yes first: unlocking a lock,
/// opening a garage door or gate, and disarming security.
enum SensitiveActionPolicy {
    /// True when this command on this accessory needs confirmation.
    static func requiresConfirmation(_ command: AccessoryCommand, on accessory: HomeAccessory) -> Bool {
        switch command {
        case .unlock:
            return true
        case .open:
            return isEntrance(accessory)
        case .setPosition(let value):
            return value > 0 && isEntrance(accessory)
        case .setPower(false), .toggle:
            return accessory.kind == .securitySystem
        default:
            return false
        }
    }

    /// Garage doors, and covers that are really gates or doors (Home Assistant
    /// reports those as covers). Blinds and shades open without asking.
    static func isEntrance(_ accessory: HomeAccessory) -> Bool {
        if accessory.kind == .garageDoor { return true }
        guard accessory.kind == .cover else { return false }
        let name = accessory.name.lowercased()
        return ["garage", "gate", "door"].contains { name.contains($0) }
    }

    /// The spoken question, for example "Unlock the Front Door?".
    static func question(for command: AccessoryCommand, accessories: [HomeAccessory]) -> String {
        let names = ListFormatter.localizedString(byJoining: accessories.map { "the \($0.name)" })
        switch command {
        case .unlock: return "Unlock \(names)?"
        case .open, .setPosition: return "Open \(names)?"
        default: return "Disarm \(names)?"
        }
    }

    /// Tools from other modules whose names suggest a sensitive action, with the question to ask.
    static func question(forToolNamed name: String) -> String? {
        let lowered = name.lowercased()
        let sensitive = lowered.contains("unlock") || lowered.contains("disarm")
            || (lowered.contains("open") && (lowered.contains("garage") || lowered.contains("gate")))
        guard sensitive else { return nil }
        let readable = lowered.replacingOccurrences(of: "_", with: " ")
        return "Allow \(readable)?"
    }
}
