import Foundation

/// One calendar's choice in Settings' list of every calendar: automatic, or a
/// fixed audience. Calendars several members share are edited in the rows above
/// the list, so they show as `.several` here.
public enum CalendarAudienceChoice: Hashable, Sendable {
    /// No choice saved. The name suggestion, then Calendars Nobody Chose, decide.
    case automatic
    case everyone
    case member(UUID)
    case several(Set<UUID>)
    case hidden

    /// The choice that matches a saved assignment (nil when there is none).
    public init(assignment: CalendarAudience?) {
        switch assignment {
        case nil: self = .automatic
        case .everyone: self = .everyone
        case .hidden: self = .hidden
        case .members(let ids):
            if ids.isEmpty {
                self = .hidden
            } else if ids.count == 1, let id = ids.first {
                self = .member(id)
            } else {
                self = .several(ids)
            }
        }
    }

    /// The assignment to save, or nil to go back to automatic.
    public var assignment: CalendarAudience? {
        switch self {
        case .automatic: nil
        case .everyone: .everyone
        case .member(let id): .members([id])
        case .several(let ids): .members(ids)
        case .hidden: .hidden
        }
    }
}
