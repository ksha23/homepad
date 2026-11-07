import Foundation

/// A city on the World Clock.
public struct WorldClockCity: Codable, Hashable, Identifiable, Sendable {
    public var id: String { "\(name)|\(timeZoneID)" }
    public var name: String
    /// IANA identifier such as "Europe/London".
    public var timeZoneID: String

    public init(name: String, timeZoneID: String) {
        self.name = name
        self.timeZoneID = timeZoneID
    }

    public var timeZone: TimeZone { TimeZone(identifier: timeZoneID) ?? .current }

    /// What a new HomePad shows before anyone edits the list.
    public static let defaults: [WorldClockCity] = [
        WorldClockCity(name: "New York", timeZoneID: "America/New_York"),
        WorldClockCity(name: "London", timeZoneID: "Europe/London"),
        WorldClockCity(name: "Tokyo", timeZoneID: "Asia/Tokyo"),
        WorldClockCity(name: "Sydney", timeZoneID: "Australia/Sydney"),
    ]
}

/// The curated World Clock looks.
public enum WorldClockStyle: String, Codable, CaseIterable, Sendable {
    /// Analog face with hour numerals.
    case analog
    /// Analog face with tick marks only.
    case minimal
    /// Large digital time.
    case digital

    public var title: String {
        switch self {
        case .analog: "Analog"
        case .minimal: "Minimal"
        case .digital: "Digital"
        }
    }

    /// The symbol the header shows when it is short of room for the title.
    public var systemImage: String {
        switch self {
        case .analog: "clock"
        case .minimal: "circle.dotted"
        case .digital: "123.rectangle"
        }
    }
}
