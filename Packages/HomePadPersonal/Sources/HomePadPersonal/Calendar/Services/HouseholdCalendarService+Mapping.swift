import Foundation
import HomePadCore

/// Who each calendar and reminders list belongs to, edited in Settings.
extension HouseholdCalendarService {
    /// Every calendar or list of one kind, unfiltered, for the mapping screens.
    func allSources(_ kind: CalendarSource.Kind) -> [CalendarSource] {
        kind == .events ? allEventCalendars : allReminderLists
    }

    /// Identifiers currently assigned to a row (Everyone or one member).
    public func selection(for target: CalendarAudienceTarget, kind: CalendarSource.Kind) -> Set<String> {
        policy.selection(for: target, among: allSources(kind), adminIDs: viewer.adminIDs)
    }

    /// Titles currently assigned to a row, for the row's subtitle.
    public func titles(for target: CalendarAudienceTarget, kind: CalendarSource.Kind) -> [String] {
        let ids = selection(for: target, kind: kind)
        return allSources(kind).filter { ids.contains($0.id) }.map(\.title)
    }

    /// Saves what someone picked in the calendar chooser for one row.
    public func applySelection(_ ids: Set<String>, for target: CalendarAudienceTarget, kind: CalendarSource.Kind) {
        var updated = policy
        updated.apply(selection: ids, for: target, among: allSources(kind), adminIDs: viewer.adminIDs)
        settings[PersonalSettings.calendarAudiences] = updated.assignments
    }

    public var unassignedPolicy: UnassignedCalendarPolicy {
        get { settings[PersonalSettings.unassignedCalendars] }
        set { settings[PersonalSettings.unassignedCalendars] = newValue }
    }
}
