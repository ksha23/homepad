import Foundation

/// The Reminders view someone chose, as saved: a smart list, or a list by its
/// identifier, so a renamed list stays chosen.
enum ReminderSelection: Codable, Hashable, Sendable {
    case today
    case scheduled
    case all
    case list(id: String)

    init(_ filter: ReminderFilter) {
        switch filter {
        case .today: self = .today
        case .scheduled: self = .scheduled
        case .all: self = .all
        case .list(let list): self = .list(id: list.id)
        }
    }

    /// The view to show, or nil when the list is gone or not visible to the
    /// person at the screen.
    func filter(visibleLists: [CalendarSource]) -> ReminderFilter? {
        switch self {
        case .today: .today
        case .scheduled: .scheduled
        case .all: .all
        case .list(let id): visibleLists.first { $0.id == id }.map(ReminderFilter.list)
        }
    }
}
