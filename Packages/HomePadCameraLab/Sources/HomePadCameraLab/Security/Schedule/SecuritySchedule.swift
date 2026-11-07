import Foundation

/// When Security Camera mode actually runs the camera. Curated presets only.
enum SecuritySchedule: String, Codable, CaseIterable, Identifiable, Sendable {
    /// Whenever Security Camera mode is on.
    case always
    /// From 11 PM to 7 AM.
    case atNight
    /// After nobody has been seen or touched the screen for a while.
    case whenAway

    static let nightStartHour = 23
    static let nightEndHour = 7
    static let awayAfter: TimeInterval = 20 * 60

    var id: String { rawValue }

    var title: String {
        switch self {
        case .always: "Always"
        case .atNight: "At Night"
        case .whenAway: "When Away"
        }
    }

    var detail: String {
        switch self {
        case .always: "Watches the whole time Security Camera is on."
        case .atNight: "Watches from 11 PM to 7 AM."
        case .whenAway: "Watches after nobody has been seen for 20 minutes. Touching the screen ends it."
        }
    }

    /// Whether the camera should be watching right now.
    /// - Parameter lastSeenSomeone: the last time presence sensing saw someone or the screen was touched.
    func shouldWatch(now: Date, calendar: Calendar = .current, lastSeenSomeone: Date?) -> Bool {
        switch self {
        case .always:
            return true
        case .atNight:
            let hour = calendar.component(.hour, from: now)
            return hour >= Self.nightStartHour || hour < Self.nightEndHour
        case .whenAway:
            guard let lastSeenSomeone else { return true }
            return now.timeIntervalSince(lastSeenSomeone) >= Self.awayAfter
        }
    }
}
