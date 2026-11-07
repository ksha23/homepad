import Foundation

/// Where a calendar's audience comes from.
public enum CalendarAudienceOrigin: Equatable, Sendable {
    /// Someone chose it in Settings.
    case assigned
    /// Suggested from the calendar's name (holidays, Family, Groceries).
    case suggested
    /// Nobody chose, so the rule for calendars nobody chose applies.
    /// Calendars added to the iPad later land here too.
    case unassignedRule
}

/// Who sees one calendar, why, and whether the current viewer sees it.
public struct CalendarStatus: Equatable, Sendable {
    public var audience: CalendarAudience
    public var origin: CalendarAudienceOrigin
    public var isVisibleNow: Bool
}

/// Calendars the current viewer cannot see, split by why, so screens can say
/// so instead of silently showing less.
public struct HiddenCalendars: Equatable, Sendable {
    /// Personal to someone who is not recognized right now.
    public var awaitingOwner: [CalendarSource] = []
    /// Hidden for everyone by a choice in Settings.
    public var hiddenInSettings: [CalendarSource] = []

    public var isEmpty: Bool { awaitingOwner.isEmpty && hiddenInSettings.isEmpty }
}

extension CalendarVisibilityPolicy {
    public func origin(for source: CalendarSource) -> CalendarAudienceOrigin {
        if assignments[source.id] != nil { return .assigned }
        if source.suggestedAudience != nil { return .suggested }
        return .unassignedRule
    }

    public func status(of source: CalendarSource, for viewer: CalendarViewer) -> CalendarStatus {
        CalendarStatus(
            audience: audience(for: source, adminIDs: viewer.adminIDs),
            origin: origin(for: source),
            isVisibleNow: isVisible(source, to: viewer)
        )
    }

    /// The calendars among `sources` that `viewer` cannot see, order preserved.
    public func hidden(_ sources: [CalendarSource], from viewer: CalendarViewer) -> HiddenCalendars {
        var result = HiddenCalendars()
        for source in sources where !isVisible(source, to: viewer) {
            if case .members(let owners) = audience(for: source, adminIDs: viewer.adminIDs), !owners.isEmpty {
                result.awaitingOwner.append(source)
            } else {
                result.hiddenInSettings.append(source)
            }
        }
        return result
    }

    /// Sets one calendar's audience from Settings. Nil goes back to automatic:
    /// the name suggestion, then the rule for calendars nobody chose.
    public mutating func assign(_ audience: CalendarAudience?, toCalendar id: String) {
        assignments[id] = audience
    }
}
