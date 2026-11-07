import Foundation

/// What iPadOS lets HomePad do with calendars, from EventKit's authorization status.
public enum CalendarAccessState: Equatable, Sendable {
    case notDetermined
    /// Read and write. The only state in which events can show.
    case fullAccess
    /// "Add Events Only" in the Settings app. HomePad can add events but cannot read any.
    case writeOnly
    case denied
    /// Screen Time or a device profile blocks access.
    case restricted

    /// The value shown in Settings, matching the Settings app's wording where it has one.
    public var title: String {
        switch self {
        case .notDetermined: "Not Asked Yet"
        case .fullAccess: "Full Access"
        case .writeOnly: "Add Events Only"
        case .denied: "None"
        case .restricted: "Restricted"
        }
    }
}
