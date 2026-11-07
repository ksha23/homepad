import Foundation

/// How close the nearest person is. Drives HomeView-style distance-adaptive UI:
/// big glanceable info when `far`, more detail when `near`.
public enum ProximityLevel: Int, Codable, Comparable, Sendable, CaseIterable {
    case nobody = 0
    case far = 1        // more than ~2.5 m, or seen but too small to measure
    case mid = 2        // ~1 to 2.5 m
    case near = 3       // within arm's reach

    public static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }

    /// Maps a measured distance to a level. Thresholds are shared so every module agrees.
    public static func from(distanceMeters: Double) -> ProximityLevel {
        switch distanceMeters {
        case ..<1.0: .near
        case ..<2.5: .mid
        default: .far
        }
    }
}

/// Which sensor produced a presence reading.
public enum PresenceSource: String, Codable, Sendable {
    case trueDepth      // ARKit face tracking on the Face ID (IR) camera, works in the dark
    case frontCamera    // Vision on the RGB front camera
    case microphone     // speech or sound activity
    case touch
    case none
}

/// Room lighting bucket used for brightness and night mode.
public enum AmbientLight: String, Codable, Sendable {
    case dark, dim, normal, bright
}

/// One fused reading from all presence sensors.
public struct PresenceSnapshot: Equatable, Sendable {
    public var isSomeonePresent: Bool
    public var peopleCount: Int
    public var proximity: ProximityLevel
    public var nearestDistanceMeters: Double?
    /// True when someone is looking at the screen (gaze from TrueDepth or face pose).
    public var isLookingAtScreen: Bool
    public var recognizedMemberID: UUID?
    public var ambientLight: AmbientLight?
    /// Smoothed room light in lux, when a camera can measure it. Drives auto-brightness.
    public var ambientLux: Double?
    public var source: PresenceSource
    public var lastActivity: Date

    public init(
        isSomeonePresent: Bool = false, peopleCount: Int = 0, proximity: ProximityLevel = .nobody,
        nearestDistanceMeters: Double? = nil, isLookingAtScreen: Bool = false,
        recognizedMemberID: UUID? = nil, ambientLight: AmbientLight? = nil,
        source: PresenceSource = .none, lastActivity: Date = .distantPast, ambientLux: Double? = nil
    ) {
        self.isSomeonePresent = isSomeonePresent
        self.peopleCount = peopleCount
        self.proximity = proximity
        self.nearestDistanceMeters = nearestDistanceMeters
        self.isLookingAtScreen = isLookingAtScreen
        self.recognizedMemberID = recognizedMemberID
        self.ambientLight = ambientLight
        self.ambientLux = ambientLux
        self.source = source
        self.lastActivity = lastActivity
    }

    public static let empty = PresenceSnapshot()
}

/// What the display should be doing. The shell's kiosk controller computes this
/// from presence, ambient light, time of day and settings.
public enum DisplayCondition: String, Codable, Sendable {
    case active     // someone is interacting
    case ambient    // showing a face, normal brightness
    case dimmed     // nobody near, low brightness
    case night      // dark room, red-tinted night mode
    case sleeping   // nobody around for a while, near-black screen

    /// True when the display shows content at normal brightness, the only time
    /// continuous motion is worth its power.
    public var allowsMotion: Bool {
        switch self {
        case .active, .ambient: true
        case .dimmed, .night, .sleeping: false
        }
    }
}

/// Hand gestures the Presence module can recognize in front of the screen.
public enum HandGesture: String, Codable, Sendable {
    case openPalm       // stop / pause
    case pinch
}

/// Head gestures from AirPods motion sensors (CMHeadphoneMotionManager).
/// Used to answer yes or no prompts hands-free, for example "Unlock the front door?".
public enum HeadGesture: String, Codable, Sendable {
    case nod        // yes
    case shake      // no
}
