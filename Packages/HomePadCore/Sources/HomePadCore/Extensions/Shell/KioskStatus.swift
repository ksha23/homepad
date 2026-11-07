import Foundation

/// What the shell shows and how the iPad is powered, for modules that report it
/// elsewhere, such as Home Assistant. The shell's kiosk keeps it current in
/// `AppServices.kioskStatus`, checking once a second and writing only changes.
/// The display condition and the app on screen are `AppServices.displayCondition`
/// and `AppServices.visibleAppID`.
public struct KioskStatus: Equatable, Sendable {
    /// What fills the screen.
    public enum Surface: String, Sendable {
        case face, homeScreen, app
    }

    /// Where the iPad's power comes from.
    public enum Power: String, Sendable {
        case charging, full, unplugged
    }

    public var surface: Surface
    /// The face on screen, or the one the Home Screen and apps sit on. A face ID
    /// from `ModuleRegistry.faces`.
    public var faceID: String?
    /// Screen brightness from 0 to 1, in whole percent.
    public var brightness: Double?
    /// Battery charge from 0 to 1. Nil when unknown, as in the simulator.
    public var batteryLevel: Double?
    /// Nil when unknown.
    public var power: Power?

    public init(surface: Surface = .face, faceID: String? = nil, brightness: Double? = nil,
                batteryLevel: Double? = nil, power: Power? = nil) {
        self.surface = surface
        self.faceID = faceID
        self.brightness = brightness
        self.batteryLevel = batteryLevel
        self.power = power
    }
}

/// Requests other modules send the shell's kiosk through the event bus, since
/// only the kiosk sets brightness and puts the screen to sleep.
public enum KioskRequest {
    /// `.custom` name: the screen sleeps now and stays asleep until someone
    /// touches it, a wake event arrives or someone walks up. No payload.
    public static let sleep = "shell.kiosk.sleep"
    /// `.custom` name: set the brightness by hand, as Control Center does. It holds
    /// until the display condition changes. Payload: a number from 0 to 1.
    public static let setBrightness = "shell.kiosk.setBrightness"
    /// `.custom` name: forget a face asked for with `.showFace` and show the
    /// usual face, the person's own or the household's. No payload.
    public static let showDefaultFace = "shell.kiosk.showDefaultFace"
}

public extension HomePadEvent {
    /// Puts the screen to sleep now (see `KioskRequest.sleep`).
    static var sleepDisplay: HomePadEvent { .custom(name: KioskRequest.sleep, payload: .null) }

    /// Sets the screen's brightness by hand, from 0 to 1 (see `KioskRequest.setBrightness`).
    static func setBrightness(_ level: Double) -> HomePadEvent {
        .custom(name: KioskRequest.setBrightness, payload: .number(min(max(level, 0), 1)))
    }

    /// Shows the usual face again (see `KioskRequest.showDefaultFace`).
    static var showDefaultFace: HomePadEvent { .custom(name: KioskRequest.showDefaultFace, payload: .null) }
}
