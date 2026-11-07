import Foundation
import HomePadCore

/// Everything the sensors are made from, read from the services HomePad
/// already has: presence, the household, the kiosk and the registry. Plain
/// values, so the sensors are tested without the services.
struct MobileAppSensorInputs: Equatable {
    var presence: PresenceSnapshot
    /// The member recognized or verified at the screen. Nil for a guest, and for
    /// a member only picked by hand in the People menu.
    var recognizedName: String?
    var display: DisplayCondition
    var kiosk: KioskStatus
    var faceTitle: String?
    /// The app on screen, nil on a face and the Home Screen.
    var appID: String?
    var appTitle: String?

    /// The HomePad as it is right now.
    @MainActor
    static func current(services: AppServices, registry: ModuleRegistry?) -> MobileAppSensorInputs {
        let kiosk = services.kioskStatus
        let appID = services.visibleAppID
        return MobileAppSensorInputs(
            presence: services.presence.snapshot,
            recognizedName: services.household.unlockedMember?.name,
            display: services.displayCondition,
            kiosk: kiosk,
            faceTitle: kiosk.faceID.flatMap { registry?.face($0)?.title },
            appID: appID,
            appTitle: appID.flatMap { registry?.app($0)?.title }
        )
    }

    /// Every sensor's value, in `MobileAppSensor.allCases` order.
    var states: [MobileAppSensorState] {
        MobileAppSensor.allCases.map(state(of:))
    }

    func state(of sensor: MobileAppSensor) -> MobileAppSensorState {
        switch sensor {
        case .presence:
            let present = presence.isSomeonePresent
            return MobileAppSensorState(sensor: sensor, state: .bool(present),
                                        icon: present ? "mdi:account" : "mdi:account-outline")
        case .proximity:
            return MobileAppSensorState(sensor: sensor, state: .string(proximity), icon: "mdi:signal-distance-variant")
        case .recognized:
            return MobileAppSensorState(sensor: sensor, state: .string(recognizedName ?? "Guest"), icon: "mdi:face-recognition")
        case .roomLight:
            return roomLight
        case .screen:
            return MobileAppSensorState(sensor: sensor, state: .string(screen), icon: screenIcon,
                                        attributes: ["display": .string(display.rawValue)])
        case .face:
            var attributes: [String: JSONValue] = [:]
            if let id = kiosk.faceID { attributes["id"] = .string(id) }
            let title = faceTitle ?? kiosk.faceID
            return MobileAppSensorState(sensor: sensor, state: title.map { .string($0) } ?? MobileAppSensorState.unavailable,
                                        icon: "mdi:clock-time-four-outline", attributes: attributes)
        case .app:
            guard let appID else {
                return MobileAppSensorState(sensor: sensor, state: "None", icon: "mdi:apps")
            }
            return MobileAppSensorState(sensor: sensor, state: .string(appTitle ?? appID), icon: "mdi:apps",
                                        attributes: ["id": .string(appID)])
        case .brightness:
            return MobileAppSensorState(sensor: sensor, state: Self.percent(kiosk.brightness), icon: "mdi:brightness-6")
        case .battery:
            return MobileAppSensorState(sensor: sensor, state: Self.percent(kiosk.batteryLevel), icon: batteryIcon)
        case .charging:
            guard let power = kiosk.power else {
                return MobileAppSensorState(sensor: sensor, state: MobileAppSensorState.unavailable, icon: "mdi:power-plug")
            }
            // On while the iPad is on power, full or charging, as a kiosk should be.
            let onPower = power != .unplugged
            return MobileAppSensorState(sensor: sensor, state: .bool(onPower),
                                        icon: onPower ? "mdi:power-plug" : "mdi:power-plug-off",
                                        attributes: ["battery_state": .string(power.rawValue)])
        }
    }

    /// "nobody", "far", "mid" or "near".
    private var proximity: String {
        guard presence.isSomeonePresent else { return "nobody" }
        switch presence.proximity {
        case .nobody, .far: return "far"
        case .mid: return "mid"
        case .near: return "near"
        }
    }

    /// Asleep and night cover whatever is on screen, since that is what someone
    /// in the room sees.
    private var screen: String {
        switch display {
        case .sleeping: return "asleep"
        case .night: return "night"
        case .active, .ambient, .dimmed: break
        }
        switch kiosk.surface {
        case .face: return "face"
        case .homeScreen: return "home_screen"
        case .app: return "app"
        }
    }

    private var screenIcon: String {
        switch display {
        case .sleeping: "mdi:sleep"
        case .night: "mdi:weather-night"
        default: "mdi:tablet"
        }
    }

    /// Lux while a camera measures it, with the level HomePad sorts it into.
    private var roomLight: MobileAppSensorState {
        var attributes: [String: JSONValue] = [:]
        if let level = presence.ambientLight { attributes["level"] = .string(level.rawValue) }
        guard let lux = presence.ambientLux else {
            return MobileAppSensorState(sensor: .roomLight, state: MobileAppSensorState.unavailable,
                                        icon: "mdi:brightness-5", attributes: attributes)
        }
        // Tenths only matter in a dark room.
        let rounded = lux < 10 ? (lux * 10).rounded() / 10 : lux.rounded()
        return MobileAppSensorState(sensor: .roomLight, state: .number(rounded), icon: "mdi:brightness-5", attributes: attributes)
    }

    /// The Material Design battery icon for the level, in tens, with the charging bolt on power.
    private var batteryIcon: String {
        guard let level = kiosk.batteryLevel else { return "mdi:battery-unknown" }
        let tens = Int((level * 10).rounded()) * 10
        let charging = kiosk.power == .charging || kiosk.power == .full
        let base = charging ? "mdi:battery-charging" : "mdi:battery"
        switch tens {
        case ..<10: return base + "-outline"
        case 100...: return charging ? base + "-100" : base
        default: return "\(base)-\(tens)"
        }
    }

    /// A 0 to 1 level as a whole percent, or unavailable.
    private static func percent(_ level: Double?) -> JSONValue {
        level.map { .number(($0 * 100).rounded()) } ?? MobileAppSensorState.unavailable
    }
}
