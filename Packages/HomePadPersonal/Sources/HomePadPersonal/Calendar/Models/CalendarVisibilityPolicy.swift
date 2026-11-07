import Foundation

/// Decides which calendars and reminder lists a viewer may see.
///
/// Resolution order for one calendar: the explicit assignment from Settings,
/// then the calendar's suggested audience (holidays, the Family Sharing
/// calendar, the Groceries list), then the unassigned policy.
public struct CalendarVisibilityPolicy: Equatable, Sendable {
    /// Explicit assignments keyed by calendar identifier.
    public var assignments: [String: CalendarAudience]
    public var unassigned: UnassignedCalendarPolicy

    public init(assignments: [String: CalendarAudience] = [:], unassigned: UnassignedCalendarPolicy = .admins) {
        self.assignments = assignments
        self.unassigned = unassigned
    }

    /// The effective audience of one calendar.
    ///
    /// With no admins (nobody added in People yet) nobody can ever be
    /// recognized, so calendars nobody chose show for everyone instead of
    /// never showing. Settings treats a household without admins as open too.
    public func audience(for source: CalendarSource, adminIDs: Set<UUID>) -> CalendarAudience {
        if let assigned = assignments[source.id] { return assigned }
        if let suggested = source.suggestedAudience { return suggested }
        switch unassigned {
        case .admins: return adminIDs.isEmpty ? .everyone : .members(adminIDs)
        case .everyone: return .everyone
        case .hidden: return .hidden
        }
    }

    /// Whether `viewer` may see `source` right now.
    public func isVisible(_ source: CalendarSource, to viewer: CalendarViewer) -> Bool {
        switch audience(for: source, adminIDs: viewer.adminIDs) {
        case .everyone:
            return true
        case .hidden:
            return false
        case .members(let ids):
            guard let member = viewer.unlockedMemberID else { return false }
            return ids.contains(member)
        }
    }

    /// The subset of `sources` that `viewer` may see, order preserved.
    public func visible(_ sources: [CalendarSource], to viewer: CalendarViewer) -> [CalendarSource] {
        sources.filter { isVisible($0, to: viewer) }
    }

    /// True when the calendar is visible to everyone, guests included.
    public func isShared(_ source: CalendarSource, adminIDs: Set<UUID>) -> Bool {
        audience(for: source, adminIDs: adminIDs) == .everyone
    }
}
