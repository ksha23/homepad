import Foundation
import HomePadCore
import Observation

/// Calendars and reminders for the whole household. Installed into `services.calendar`.
///
/// Every read and write goes through `CalendarVisibilityPolicy`: shared
/// calendars always show, and a member's personal calendars show only while
/// that member is recognized (`Household.isPersonalContentUnlocked`). The
/// recognized member's own iPhone calendars and lists join them while that
/// member is the one recognized (`HouseholdCalendarService+Phone`).
@MainActor
@Observable
public final class HouseholdCalendarService: CalendarService {
    /// Bumped when calendars change on another device, so views reload.
    public internal(set) var changeToken = 0
    /// Bumped after access is granted or demo data is toggled.
    public private(set) var accessToken = 0

    @ObservationIgnored let household: Household
    @ObservationIgnored let settings: SettingsStore
    /// The recognized person's own iPhone calendars, read when needed, since
    /// the Connect module installs them after this service is made.
    @ObservationIgnored let phoneSource: @MainActor () -> (any PhoneCalendarsService)?
    @ObservationIgnored private lazy var eventKit: EventKitCalendarBackend = makeEventKitBackend()
    @ObservationIgnored private lazy var demo: DemoCalendarBackend = makeDemoBackend()

    public init(household: Household, settings: SettingsStore,
                phoneCalendars: @escaping @MainActor () -> (any PhoneCalendarsService)? = { nil }) {
        self.household = household
        self.settings = settings
        self.phoneSource = phoneCalendars
        writeDiagnosticReportIfAsked()
    }

    // MARK: Background refresh

    /// Asks the iPad's calendar and reminder accounts for changes, for the
    /// calendar background task. New events arrive through EventKit's change
    /// notification, which reloads every view that shows them.
    func refreshSources() -> BackgroundTaskOutcome {
        if isUsingDemoData { return .skipped("Demo calendars stand in for this iPad's own.") }
        guard backend.hasEventAccess || backend.hasReminderAccess else {
            return .skipped("Calendar and Reminders access has not been allowed.")
        }
        backend.refreshSources()
        return .done("Asked this iPad's calendar and reminder accounts for changes.")
    }

    // MARK: Backend selection

    /// True while demo calendars and reminders stand in for the iPad's own.
    public var isUsingDemoData: Bool { settings[PersonalSettings.demoData] }

    var backend: any CalendarBackend {
        isUsingDemoData ? demo : eventKit
    }

    /// The EventKit backend, for the system editors (EventKitUI) that need its store.
    var eventKitBackend: EventKitCalendarBackend? {
        isUsingDemoData ? nil : eventKit
    }

    // MARK: Privacy

    /// Who is looking right now, from the household's recognition state.
    public var viewer: CalendarViewer {
        _ = household.activeMemberID
        return CalendarViewer(
            memberID: household.activeMemberID,
            isUnlocked: household.isPersonalContentUnlocked,
            adminIDs: Set(household.members.filter(\.isAdmin).map(\.id))
        )
    }

    public var policy: CalendarVisibilityPolicy {
        CalendarVisibilityPolicy(
            assignments: settings[PersonalSettings.calendarAudiences],
            unassigned: settings[PersonalSettings.unassignedCalendars]
        )
    }

    /// Changes whenever anything that affects what is visible changes.
    /// Views reload with `.task(id: calendar.reloadKey)`.
    public var reloadKey: String {
        "\(changeToken)-\(accessToken)-\(settings.revision)-\(viewer.memberID?.uuidString ?? "guest")-\(viewer.isUnlocked)-\(phoneSnapshot?.revision ?? -1)"
    }

    // MARK: Access (CalendarService)

    public var hasAccess: Bool {
        _ = accessToken
        return backend.hasEventAccess
    }

    public var hasReminderAccess: Bool {
        _ = accessToken
        return backend.hasReminderAccess
    }

    public var isEventAccessDenied: Bool {
        _ = accessToken
        return backend.isEventAccessDenied
    }

    public var isReminderAccessDenied: Bool {
        _ = accessToken
        return backend.isReminderAccessDenied
    }

    public var eventAccessState: CalendarAccessState {
        _ = accessToken
        return backend.eventAccessState
    }

    public func requestAccess() async -> Bool {
        let granted = await backend.requestEventAccess()
        accessToken += 1
        return granted
    }

    public func requestReminderAccess() async -> Bool {
        let granted = await backend.requestReminderAccess()
        if granted { await ensureDefaultList() }
        accessToken += 1
        return granted
    }

    // MARK: Calendars

    // Each list reads the change tokens, so a view that shows calendars redraws
    // when one is added on the iPad (a new subscription, say) or access changes.

    /// Every event calendar on the iPad, unfiltered. For Settings only.
    public var allEventCalendars: [CalendarSource] {
        _ = (changeToken, accessToken)
        return backend.eventCalendars()
    }

    /// Every reminders list on the iPad, unfiltered. For Settings only.
    public var allReminderLists: [CalendarSource] {
        _ = (changeToken, accessToken)
        return backend.reminderLists()
    }

    /// Event calendars the current viewer may see: the iPad's, then their own phone's.
    public var visibleCalendars: [CalendarSource] { policy.visible(allEventCalendars, to: viewer) + phoneEventCalendars }

    /// Reminders lists the current viewer may see: the iPad's, then their own phone's.
    public var visibleReminderLists: [CalendarSource] { policy.visible(allReminderLists, to: viewer) + phoneReminderLists }

    /// True when a calendar or list is shared with everyone. Never one on someone's phone.
    func isShared(_ source: CalendarSource) -> Bool {
        source.phone == nil && policy.isShared(source, adminIDs: viewer.adminIDs)
    }

    // MARK: Events

    /// Events between two dates from calendars the viewer may see and left
    /// checked in the Calendars list. The app, Up Next and (through
    /// `events(from:to:)`) the faces all read events here.
    public func agenda(from start: Date, to end: Date) -> [PersonalEvent] {
        let shown = shownCalendars
        guard !shown.isEmpty else { return [] }
        let own = Set(shown.filter { $0.phone == nil }.map(\.id))
        let onIPad = own.isEmpty ? [] : backend.events(from: start, to: end, calendarIDs: own)
        let onPhone = phoneEvents(from: start, to: end, calendarIDs: Set(shown.filter { $0.phone != nil }.map(\.id)), besides: onIPad)
        guard !onPhone.isEmpty else { return onIPad }
        return (onIPad + onPhone).sorted { ($0.isAllDay ? 0 : 1, $0.start) < ($1.isAllDay ? 0 : 1, $1.start) }
    }

    public func events(from start: Date, to end: Date) async -> [CalendarItem] {
        let shared = Set(visibleCalendars.filter(isShared).map(\.id))
        return agenda(from: start, to: end).map { event in
            var item = event.calendarItem
            item.isShared = shared.contains(event.calendarID)
            item.listID = event.calendarID
            return item
        }
    }

    /// The writable calendar new events should land in for the current viewer:
    /// the recognized member's own calendar on the iPad first, then their
    /// phone's default calendar, then a shared one. Checked calendars come
    /// first, so a new event shows where it was added.
    public func preferredCalendarForNewEvents() -> CalendarSource? {
        let writable = visibleCalendars.filter { $0.allowsModifications && !$0.isSubscribed }
        let shown = Set(shownCalendars.map(\.id))
        return preferredCalendar(among: writable.filter { shown.contains($0.id) }) ?? preferredCalendar(among: writable)
    }

    private func preferredCalendar(among writable: [CalendarSource]) -> CalendarSource? {
        let adminIDs = viewer.adminIDs
        if let member = viewer.unlockedMemberID,
           let own = writable.first(where: { $0.phone == nil && policy.audience(for: $0, adminIDs: adminIDs) == .members([member]) }) {
            return own
        }
        if let phone = writable.first(where: { $0.phone?.isDefault == true }) ?? writable.first(where: { $0.phone != nil }) {
            return phone
        }
        if let defaultID = backend.defaultEventCalendarID(), let fallback = writable.first(where: { $0.id == defaultID }) {
            return fallback
        }
        return writable.first(where: isShared) ?? writable.first
    }

    /// Calendars the viewer may see that take new events: not subscribed and
    /// not read-only. The one new events go to by default comes first.
    public var writableCalendars: [CalendarSource] {
        let writable = visibleCalendars.filter { $0.allowsModifications && !$0.isSubscribed }
        guard let preferred = preferredCalendarForNewEvents() else { return writable }
        return [preferred] + writable.filter { $0.id != preferred.id }
    }

    public func writableEventCalendars() async -> [EventCalendarInfo] {
        writableCalendars.map { source in
            EventCalendarInfo(id: source.id, title: source.title, colorHex: source.colorHex,
                              accountName: source.accountName, isShared: isShared(source))
        }
    }

    /// Adds an event to the calendar the draft names, which must be one the
    /// viewer may see and write to, or else to the viewer's preferred calendar.
    /// One on the person's own phone is sent there, and shows as sending
    /// until the phone saved it.
    /// Async like the protocol's requirement, so a call from async code never
    /// resolves to `CalendarService`'s fallback, which would call back here.
    public func addEvent(_ draft: EventDraft) async throws {
        let target: CalendarSource?
        if let id = draft.calendarID {
            guard let chosen = visibleCalendars.first(where: { $0.id == id }) else { throw PersonalError.notVisible }
            guard chosen.allowsModifications, !chosen.isSubscribed else { throw PersonalError.noWritableCalendar }
            target = chosen
        } else {
            target = preferredCalendarForNewEvents()
        }
        guard let target else { throw PersonalError.noWritableCalendar }
        if target.phone != nil {
            var routed = draft
            routed.calendarID = target.id
            try phoneService().addEvent(routed)
            return
        }
        guard backend.hasEventAccess else { throw PersonalError.noCalendarAccess }
        _ = try backend.addEvent(draft, calendarID: target.id)
        changeToken += 1
    }

    public func addEvent(title: String, start: Date, end: Date) async throws {
        try await addEvent(EventDraft(title: title, start: start, end: end))
    }

    /// Call after a system editor (EventKitUI) saved changes.
    func noteExternalEdit() {
        changeToken += 1
    }

    // MARK: Private

    private func makeEventKitBackend() -> EventKitCalendarBackend {
        let backend = EventKitCalendarBackend()
        backend.onChange = { [weak self] in self?.changeToken += 1 }
        return backend
    }

    private func makeDemoBackend() -> DemoCalendarBackend {
        let backend = DemoCalendarBackend()
        backend.onChange = { [weak self] in self?.changeToken += 1 }
        return backend
    }
}
