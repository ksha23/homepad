import Foundation
import HomePadCore

/// Why each calendar shows or not, for Settings and for the apps' notes.
extension HouseholdCalendarService {
    /// Member names by identifier, for labels such as "Shows only while Kyle is recognized".
    var memberNames: [UUID: String] {
        Dictionary(household.members.map { ($0.id, $0.name) }, uniquingKeysWith: { first, _ in first })
    }

    /// Who sees one calendar, why, and whether it shows right now.
    public func status(of source: CalendarSource) -> CalendarStatus {
        policy.status(of: source, for: viewer)
    }

    /// The calendars or lists of one kind the current viewer cannot see, by reason.
    public func hiddenCalendars(_ kind: CalendarSource.Kind) -> HiddenCalendars {
        policy.hidden(allSources(kind), from: viewer)
    }

    /// A sentence or two saying what is hidden and why, or nil when nothing is.
    public func hiddenNote(_ kind: CalendarSource.Kind) -> String? {
        let viewer = viewer
        let isAdmin = viewer.unlockedMemberID.map { viewer.adminIDs.contains($0) } ?? false
        return CalendarAudienceText.hiddenNote(hiddenCalendars(kind), kind: kind, showsNames: isAdmin)
    }

    /// The choice saved for one calendar in Settings.
    public func choice(for source: CalendarSource) -> CalendarAudienceChoice {
        CalendarAudienceChoice(assignment: policy.assignments[source.id])
    }

    /// Saves a choice for one calendar. `.automatic` removes the saved choice.
    public func setChoice(_ choice: CalendarAudienceChoice, for source: CalendarSource) {
        var updated = policy
        updated.assign(choice.assignment, toCalendar: source.id)
        settings[PersonalSettings.calendarAudiences] = updated.assignments
    }

    /// Who would see a calendar with no saved choice.
    public func automaticAudience(for source: CalendarSource) -> CalendarAudience {
        var automatic = policy
        automatic.assign(nil, toCalendar: source.id)
        return automatic.audience(for: source, adminIDs: viewer.adminIDs)
    }

    /// Events between two dates from calendars that wait for their owner to be
    /// recognized. Faces use the count to say that more events exist.
    public func hiddenEventCount(from start: Date, to end: Date) async -> Int {
        let ids = Set(hiddenCalendars(.events).awaitingOwner.map(\.id))
        guard !ids.isEmpty else { return 0 }
        return backend.events(from: start, to: end, calendarIDs: ids).count
    }
}
