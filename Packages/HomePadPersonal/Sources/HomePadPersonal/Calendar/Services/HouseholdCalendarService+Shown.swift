import Foundation

/// Which calendars each person chose to show, like the Calendars list in
/// Apple's Calendar app. The choice only hides calendars the viewer may
/// already see. Who a calendar belongs to, and so who may see it, stays in
/// Settings, Personal Info (`CalendarVisibilityPolicy`), and nothing here changes it.
extension HouseholdCalendarService {
    /// The key the current choice is saved under: the active member's
    /// identifier, or "guest" while nobody is selected.
    var shownChoiceKey: String {
        viewer.memberID?.uuidString ?? "guest"
    }

    /// The person whose choice applies, or nil for guests.
    public var shownChoiceOwnerName: String? {
        household.activeMember?.name
    }

    /// Calendars the current viewer unchecked.
    var uncheckedCalendarIDs: Set<String> {
        settings[PersonalSettings.uncheckedCalendars][shownChoiceKey] ?? []
    }

    /// Calendars the viewer may see and left checked. Calendar, Up Next and
    /// the faces show events from these only.
    public var shownCalendars: [CalendarSource] {
        let unchecked = uncheckedCalendarIDs
        return visibleCalendars.filter { !unchecked.contains($0.id) }
    }

    public func isShown(_ source: CalendarSource) -> Bool {
        !uncheckedCalendarIDs.contains(source.id)
    }

    public func setShown(_ shown: Bool, for source: CalendarSource) {
        setShown(shown, ids: [source.id])
    }

    /// Checks every calendar the viewer may see. Calendars they may not see
    /// right now (their own, while not recognized) keep their checkmark.
    public func showAll() {
        setShown(true, ids: visibleCalendars.map(\.id))
    }

    /// Unchecks every calendar the viewer may see.
    public func hideAll() {
        setShown(false, ids: visibleCalendars.map(\.id))
    }

    private func setShown(_ shown: Bool, ids: [String]) {
        var all = settings[PersonalSettings.uncheckedCalendars]
        var unchecked = all[shownChoiceKey] ?? []
        if shown { unchecked.subtract(ids) } else { unchecked.formUnion(ids) }
        all[shownChoiceKey] = unchecked.isEmpty ? nil : unchecked
        settings[PersonalSettings.uncheckedCalendars] = all
    }
}
