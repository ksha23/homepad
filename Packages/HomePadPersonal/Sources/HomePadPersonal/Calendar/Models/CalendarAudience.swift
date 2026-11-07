import Foundation

/// Who may see a calendar or reminder list on this HomePad.
public enum CalendarAudience: Codable, Hashable, Sendable {
    /// A household calendar. Everyone sees it, guests included.
    case everyone
    /// Personal to these members. Shown only while one of them is the active,
    /// recognized member (`Household.isPersonalContentUnlocked`).
    case members(Set<UUID>)
    /// Never shown on this HomePad.
    case hidden
}

/// What happens to calendars nobody has assigned yet in Settings.
public enum UnassignedCalendarPolicy: String, Codable, CaseIterable, Sendable {
    /// Treat them as personal to the household's admins. The iPad's iCloud
    /// account usually belongs to whoever set it up, so this is the safe default.
    case admins
    /// Show them to everyone.
    case everyone
    /// Hide them until someone assigns them.
    case hidden

    /// Label for settings pickers.
    public var title: String {
        switch self {
        case .admins: "Belong to admins"
        case .everyone: "Shared with everyone"
        case .hidden: "Hidden"
        }
    }
}
