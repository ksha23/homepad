import Foundation
import HomePadCore

/// The recognized person's own iPhone calendars and lists
/// (`services.phoneCalendars`), shown beside the iPad's own.
///
/// They count only while the member they belong to is the one recognized
/// here, never for someone picked in People, another member or a guest, and
/// never in Settings, so an admin cannot browse them. Everything that reads
/// calendars here (the Calendar and Reminders apps, Up Next, the glance, the
/// faces and the assistant) gets them through `visibleCalendars`,
/// `visibleReminderLists`, `agenda(from:to:)` and `reminderItems`. Changes to
/// them go to the phone, and show as sending, waiting or failed until it saved them.
extension HouseholdCalendarService {
    /// What the recognized person's phone shares, or nil when nobody's shows here.
    public var phoneSnapshot: PhoneCalendarSnapshot? {
        guard let snapshot = phoneSource()?.snapshot, let member = viewer.unlockedMemberID,
              snapshot.memberID == member else { return nil }
        return snapshot
    }

    /// The phone's event calendars as sources, grouped under the phone's
    /// name in the Calendars list, the phone's default first.
    var phoneEventCalendars: [CalendarSource] {
        guard let snapshot = phoneSnapshot else { return [] }
        return snapshot.calendars.map { Self.source($0, kind: .events, from: snapshot) }
    }

    /// The phone's reminders lists as sources.
    public var phoneReminderLists: [CalendarSource] {
        guard let snapshot = phoneSnapshot else { return [] }
        return snapshot.lists.map { Self.source($0, kind: .reminders, from: snapshot) }
    }

    /// True when the person at the screen may add events to one of their phone's calendars.
    public var hasWritablePhoneCalendar: Bool {
        phoneEventCalendars.contains(where: \.allowsModifications)
    }

    /// The days the phone sent events for, to say so outside them.
    public var phoneWindow: DateInterval? { phoneSnapshot?.window }

    /// The phone's events between two dates in these calendars. One the iPad
    /// also shows (the same iCloud event on both) is left out, so it shows once.
    func phoneEvents(from start: Date, to end: Date, calendarIDs: Set<String>, besides shown: [PersonalEvent]) -> [PersonalEvent] {
        guard let snapshot = phoneSnapshot, !calendarIDs.isEmpty else { return [] }
        let calendars = Dictionary(snapshot.calendars.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let onIPad = Set(shown.compactMap { event in event.externalID.map { "\($0)|\(Int(event.start.timeIntervalSinceReferenceDate))" } })
        return snapshot.events.compactMap { event in
            guard calendarIDs.contains(event.calendarID), let calendar = calendars[event.calendarID],
                  event.start < end, event.end > start || (event.start >= start && event.end <= event.start) else { return nil }
            if let external = event.externalID, onIPad.contains("\(external)|\(Int(event.start.timeIntervalSinceReferenceDate))") {
                return nil
            }
            return PersonalEvent(
                id: event.id, title: event.title, start: event.start, end: event.end, isAllDay: event.isAllDay,
                location: event.location, notes: event.notes, calendarID: event.calendarID, calendarTitle: calendar.title,
                colorHex: calendar.colorHex, isRecurring: event.isRecurring, externalID: event.externalID,
                phoneDeviceName: snapshot.deviceName, phoneStatus: event.status
            )
        }
    }

    /// The phone's reminders in these lists.
    func phoneReminderItems(listIDs: Set<String>, includeCompleted: Bool) -> [ReminderItem] {
        guard let snapshot = phoneSnapshot, !listIDs.isEmpty else { return [] }
        let lists = Dictionary(snapshot.lists.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return snapshot.reminders.compactMap { reminder in
            guard listIDs.contains(reminder.listID), let list = lists[reminder.listID],
                  includeCompleted || !reminder.isCompleted else { return nil }
            return ReminderItem(
                id: reminder.id, title: reminder.title, isCompleted: reminder.isCompleted, due: reminder.due,
                dueHasTime: reminder.dueHasTime, listID: reminder.listID, listTitle: list.title, colorHex: list.colorHex,
                priority: reminder.priority, notes: reminder.notes, phoneDeviceName: snapshot.deviceName,
                phoneStatus: reminder.status
            )
        }
    }

    /// Changes one occurrence of an event on the person's phone. It shows
    /// changed at once, as sending, until the phone saved it.
    public func updatePhoneEvent(_ event: PersonalEvent, with draft: EventDraft) throws {
        guard event.isOnPhone, phoneEventCalendars.contains(where: { $0.id == event.calendarID }) else {
            throw PersonalError.notVisible
        }
        if let id = draft.calendarID, !phoneEventCalendars.contains(where: { $0.id == id && $0.allowsModifications }) {
            throw PersonalError.noWritableCalendar
        }
        try phoneService().updateEvent(event.id, with: draft)
    }

    /// Sends a change that waits for the phone, or failed, again now.
    public func retryPhoneChange(_ id: UUID) {
        guard phoneSnapshot != nil else { return }
        phoneSource()?.retry(id)
    }

    /// Drops a change the phone has not saved, so it never gets it.
    public func discardPhoneChange(_ id: UUID) {
        guard phoneSnapshot != nil else { return }
        phoneSource()?.discard(id)
    }

    /// The phone service, while the person at the screen has a phone here.
    func phoneService() throws -> any PhoneCalendarsService {
        guard phoneSnapshot != nil, let service = phoneSource() else { throw PersonalError.notVisible }
        return service
    }

    private static func source(_ calendar: PhoneCalendar, kind: CalendarSource.Kind, from snapshot: PhoneCalendarSnapshot) -> CalendarSource {
        CalendarSource(
            id: calendar.id, title: calendar.title, colorHex: calendar.colorHex, kind: kind,
            accountName: snapshot.deviceName, allowsModifications: calendar.allowsModifications,
            phone: CalendarSource.PhoneOrigin(memberID: snapshot.memberID, deviceName: snapshot.deviceName, isDefault: calendar.isDefault)
        )
    }
}
