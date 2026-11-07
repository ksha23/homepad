import Foundation

/// The curated timelapse intervals offered in the picker.
enum TimelapseInterval: Int, Codable, CaseIterable, Identifiable, Sendable {
    case thirtySeconds = 30
    case oneMinute = 60
    case fiveMinutes = 300
    case fifteenMinutes = 900
    case oneHour = 3600

    var id: Int { rawValue }
    var seconds: TimeInterval { TimeInterval(rawValue) }

    var title: String {
        switch self {
        case .thirtySeconds: "30 sec"
        case .oneMinute: "1 min"
        case .fiveMinutes: "5 min"
        case .fifteenMinutes: "15 min"
        case .oneHour: "1 hour"
        }
    }

    /// What each interval suits, shown under the picker.
    var suggestion: String {
        switch self {
        case .thirtySeconds: "Clouds, sunsets and busy rooms."
        case .oneMinute: "A bread dough rising or a party."
        case .fiveMinutes: "The light moving across a room through the day."
        case .fifteenMinutes: "Seedlings and flowers opening."
        case .oneHour: "Plants growing over weeks, or a pantry over a month."
        }
    }

    /// Short intervals keep the camera claimed between shots. Longer ones hand
    /// it back to presence sensing in between.
    var keepsCameraBetweenShots: Bool { self == .thirtySeconds }
}
