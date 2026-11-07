import Foundation
import HomePadCore
import Observation

/// On a HomePad: the recognized person's own iPhone calendars and reminders
/// lists, the ones they chose on that iPhone. Two kinds of data a phone visit
/// carries (`PhoneVisitClient`). Installed as `services.phoneCalendars`.
///
/// What was saved in the member's encrypted cache shows the moment the visit
/// starts, before the phone answers and while it is asleep. Each visit then
/// sends the changes made here that wait for the phone, and fetches the past
/// week to six weeks ahead of events and the open reminders. Changes made on
/// the HomePad go to the phone, waking it if needed, and show as sending,
/// waiting or failed until the phone saved them. Everything held in memory
/// goes the moment the person stops being recognized.
@MainActor
@Observable
public final class PhoneCalendarsClient: PhoneCalendarsService, PhoneVisitPart {
    public private(set) var snapshot: PhoneCalendarSnapshot?

    let kinds: Set<PhoneDataKind> = [.calendars, .reminders]
    @ObservationIgnored let visits: PhoneVisitClient
    @ObservationIgnored var cache = PhoneCalendarsCache()
    /// Every write to the cache, in order, so a save never lands after the
    /// delete that forgets a person.
    @ObservationIgnored let cacheQueue = DispatchQueue(label: "com.ksha23.homepad.phonecalendars.cache", qos: .utility)
    /// What this visit holds of the person's calendars.
    @ObservationIgnored var state: CalendarVisitState?
    @ObservationIgnored var calendar = Calendar.current
    /// How long to wait for the phone to save a change, once it is open.
    @ObservationIgnored var changeTimeout = PhoneCalendarsPolicy.changeTimeout
    @ObservationIgnored private var revision = 0
    @ObservationIgnored let log = Log.make("PhoneCalendars")

    init(visits: PhoneVisitClient) {
        self.visits = visits
    }

    func start() {
        registerHandlers()
    }

    // MARK: PhoneVisitPart

    /// Shows what was saved at once, so the person's calendars are there
    /// before the phone answers, and while it sleeps.
    func visitStarted(_ visit: PhoneVisit) {
        // Behind every save still queued, so a visit that starts again never reads an older copy.
        let cache = cache, member = visit.memberID
        let saved = cacheQueue.sync { cache.load(member: member) }
        let index = saved ?? PhoneCalendarsIndex(deviceName: visit.deviceName)
        state = CalendarVisitState(visit: visit, index: index)
        publish(visit)
    }

    /// What a visit does first: the changes that waited for the phone, then
    /// the calendars' events and the lists' reminders.
    func prefetch(_ visit: PhoneVisit) async {
        await sendOutbox(visit)
        if visit.grantedKinds.contains(.calendars) { await fetchCalendars(visit) }
        if visit.grantedKinds.contains(.reminders) { await fetchReminders(visit) }
        guard let state = current(visit) else { return }
        save(state)
        publish(visit)
    }

    func publish(_ visit: PhoneVisit) {
        guard let state = current(visit) else { return }
        var next = state.snapshot(isConnected: visits.isConnected(visit))
        next.revision = revision
        guard next != snapshot else { return }
        revision += 1
        next.revision = revision
        snapshot = next
    }

    /// The phone is back: send what waited for it.
    func phoneConnected(_ visit: PhoneVisit) {
        guard let state = current(visit), state.outbox.contains(where: { $0.state != .failed }) else { return }
        Task { await sendOutbox(visit) }
    }

    /// Nothing of the person stays in memory. What waits for the phone stays
    /// in their encrypted cache for the next visit.
    func visitEnded(_ visit: PhoneVisit) {
        guard let state, state.visit === visit else { return }
        self.state = nil
        snapshot = nil
    }

    /// Deletes what is saved of `member` for what they stopped sharing, once
    /// every write before it is done. All of it, key and folder, when they share neither.
    func forget(_ member: UUID, keeping kinds: Set<PhoneDataKind>) {
        let cache = cache
        if kinds.isEmpty {
            cacheQueue.sync { cache.delete(member: member) }
            return
        }
        let keepsCalendars = kinds.contains(.calendars)
        let keepsLists = kinds.contains(.reminders)
        let narrow: (inout PhoneCalendarsIndex) -> Void = { index in
            index.narrow(toCalendars: keepsCalendars ? Set(index.calendars.map(\.id)) : [],
                         lists: keepsLists ? Set(index.lists.map(\.id)) : [])
        }
        if let state, state.visit.memberID == member {
            narrow(&state.index)
            save(state)
            publish(state.visit)
        } else {
            cacheQueue.sync {
                guard var index = cache.load(member: member) else { return }
                narrow(&index)
                cache.save(index, member: member)
            }
        }
    }

    func prune(keeping members: Set<UUID>) {
        let cache = cache
        cacheQueue.sync { cache.prune(keeping: members) }
    }

    /// This visit's calendars while it is the one on.
    func current(_ visit: PhoneVisit) -> CalendarVisitState? {
        guard let state, state.visit === visit, visits.isCurrent(visit) else { return nil }
        return state
    }

    // MARK: PhoneCalendarsService

    public func addEvent(_ draft: EventDraft) throws {
        let state = try visiting()
        guard let calendarID = draft.calendarID else { throw PhoneCalendarError.notWritable }
        try state.checkWritable(calendarID: calendarID)
        let change = CalendarChange(fields: PhoneEventFields(draft, calendarID: calendarID))
        enqueue(.adding(change, at: visits.now()), in: state)
    }

    public func updateEvent(_ eventID: PhoneEvent.ID, with draft: EventDraft) throws {
        let state = try visiting()
        let shown = state.snapshot(isConnected: false).events.first { $0.id == eventID }
        guard let shown else { throw PhoneCalendarError.notFound }
        let calendarID = draft.calendarID ?? shown.calendarID
        try state.checkWritable(calendarID: calendarID)
        let fields = PhoneEventFields(draft, calendarID: calendarID)
        // A change that has not gone yet takes the new fields, so the phone gets one change.
        if let index = state.outbox.firstIndex(where: { $0.id == shown.status?.writeID }), var change = state.outbox[index].event {
            guard !state.inFlight.contains(state.outbox[index].id) else { throw PhoneCalendarError.busy(state.visit.deviceName) }
            change.fields = fields
            state.outbox[index].event = change
            state.outbox[index].state = .sending
            state.outbox[index].message = nil
            changed(state)
            return
        }
        guard let saved = state.index.events.first(where: { $0.id == eventID }) else { throw PhoneCalendarError.notFound }
        let change = CalendarChange(itemID: saved.itemID, occurrenceStart: saved.start, fields: fields)
        enqueue(.changing(eventID, change, at: visits.now()), in: state)
    }

    public func addReminder(title: String, due: Date?, listID: String) throws {
        let state = try visiting()
        try state.checkWritable(listID: listID)
        // A due date keeps its time, as the iPad's own lists do.
        let change = RemindersChange(add: PhoneReminderFields(listID: listID, title: title, due: due, dueHasTime: due != nil))
        enqueue(.reminder(change, listID: listID, at: visits.now()), in: state)
    }

    public func setReminderCompleted(_ reminderID: PhoneReminder.ID, completed: Bool) throws {
        let state = try visiting()
        guard let saved = state.index.reminders.first(where: { $0.id == reminderID }) else {
            // A reminder added here is checked off once the phone has it.
            throw state.outbox.contains(where: { CalendarVisitState.pendingID($0.id) == reminderID })
                ? PhoneCalendarError.busy(state.visit.deviceName) : PhoneCalendarError.notFound
        }
        try state.checkWritable(listID: saved.listID)
        // Checking off and back on before it went cancels out.
        if let index = state.outbox.firstIndex(where: { $0.reminder?.reminderID == reminderID }),
           !state.inFlight.contains(state.outbox[index].id) {
            if completed == saved.isCompleted {
                state.outbox.remove(at: index)
            } else {
                state.outbox[index].reminder?.completed = completed
                state.outbox[index].state = .sending
                state.outbox[index].message = nil
            }
            changed(state)
            return
        }
        let change = RemindersChange(reminderID: reminderID, completed: completed)
        enqueue(.reminder(change, listID: saved.listID, at: visits.now()), in: state)
    }

    public func retry(_ writeID: UUID) {
        guard let state, let index = state.outbox.firstIndex(where: { $0.id == writeID }),
              !state.inFlight.contains(writeID) else { return }
        state.outbox[index].state = .sending
        state.outbox[index].message = nil
        changed(state)
    }

    public func discard(_ writeID: UUID) {
        guard let state, !state.inFlight.contains(writeID) else { return }
        state.outbox.removeAll { $0.id == writeID }
        save(state)
        publish(state.visit)
    }

    // MARK: Plumbing

    private func visiting() throws -> CalendarVisitState {
        guard let state, visits.isCurrent(state.visit) else { throw PhoneCalendarError.notVisiting }
        return state
    }

    private func enqueue(_ write: PhoneCalendarWrite, in state: CalendarVisitState) {
        state.outbox.append(write)
        changed(state)
    }

    /// Saves and shows a change to the outbox, and sends what is ready.
    private func changed(_ state: CalendarVisitState) {
        save(state)
        publish(state.visit)
        let visit = state.visit
        Task { await sendOutbox(visit) }
    }

    /// Saves the visit's copy, only while the visit is on, so a change still
    /// on its way when the person leaves never writes back a cache that was
    /// deleted after them.
    func save(_ state: CalendarVisitState) {
        guard current(state.visit) === state else { return }
        let index = state.index
        let member = state.visit.memberID
        cacheQueue.async { [cache] in cache.save(index, member: member) }
    }
}

/// On a HomePad: what one visit holds of a person's phone calendars.
@MainActor
final class CalendarVisitState {
    let visit: PhoneVisit
    var index: PhoneCalendarsIndex
    /// Changes on their way to the phone now.
    var inFlight: Set<UUID> = []
    /// True while the outbox is being sent, so changes go one at a time, in order.
    var isSending = false

    init(visit: PhoneVisit, index: PhoneCalendarsIndex) {
        self.visit = visit
        self.index = index
    }

    var outbox: [PhoneCalendarWrite] {
        get { index.outbox }
        set { index.outbox = newValue }
    }

    /// The ID an event or reminder added here goes by until the phone saved it.
    static func pendingID(_ writeID: UUID) -> String { "pending|\(writeID.uuidString)" }

    func checkWritable(calendarID: String) throws {
        guard visit.kinds.contains(.calendars), let found = index.calendars.first(where: { $0.id == calendarID }) else {
            throw PhoneCalendarError.notFound
        }
        guard found.allowsModifications else { throw PhoneCalendarError.notWritable }
    }

    func checkWritable(listID: String) throws {
        guard visit.kinds.contains(.reminders), let found = index.lists.first(where: { $0.id == listID }) else {
            throw PhoneCalendarError.notFound
        }
        guard found.allowsModifications else { throw PhoneCalendarError.notWritable }
    }

    /// What the person sees: what the phone sent, with the changes made here on top.
    func snapshot(isConnected: Bool) -> PhoneCalendarSnapshot {
        let showsCalendars = visit.kinds.contains(.calendars)
        let showsLists = visit.kinds.contains(.reminders)
        var events = showsCalendars ? index.events : []
        var reminders = showsLists ? index.reminders : []
        for write in index.outbox {
            if let change = write.event, showsCalendars {
                let fields = change.fields
                if let eventID = write.eventID {
                    guard let at = events.firstIndex(where: { $0.id == eventID }) else { continue }
                    events[at].calendarID = fields.calendarID
                    events[at].title = fields.title
                    events[at].start = fields.start
                    events[at].end = fields.end
                    events[at].isAllDay = fields.isAllDay
                    events[at].location = fields.location
                    events[at].status = write.status
                } else {
                    events.append(PhoneEvent(id: Self.pendingID(write.id), itemID: "", calendarID: fields.calendarID,
                                             title: fields.title, start: fields.start, end: fields.end,
                                             isAllDay: fields.isAllDay, location: fields.location, status: write.status))
                }
            } else if let change = write.reminder, showsLists {
                if let add = change.add {
                    reminders.append(PhoneReminder(id: Self.pendingID(write.id), listID: add.listID, title: add.title,
                                                   due: add.due, dueHasTime: add.dueHasTime, status: write.status))
                } else if let id = change.reminderID, let completed = change.completed,
                          let at = reminders.firstIndex(where: { $0.id == id }) {
                    reminders[at].isCompleted = completed
                    reminders[at].status = write.status
                }
            }
        }
        return PhoneCalendarSnapshot(
            memberID: visit.memberID, deviceName: visit.deviceName,
            calendars: showsCalendars ? index.calendars : [], lists: showsLists ? index.lists : [],
            events: events, reminders: reminders, window: showsCalendars ? index.window : nil,
            fetchedAt: index.calendarsFetchedAt ?? index.remindersFetchedAt, isConnected: isConnected
        )
    }
}

/// Why a change to a phone's calendar or list was not taken.
enum PhoneCalendarError: LocalizedError, Equatable {
    case notVisiting
    case notFound
    case notWritable
    case busy(String)

    var errorDescription: String? {
        switch self {
        case .notVisiting: "That iPhone's calendars are not open on this HomePad right now."
        case .notFound: "That is no longer shared from the iPhone."
        case .notWritable: "That calendar or list is read-only on the iPhone."
        case .busy(let phone): "\(phone) has not saved this yet. Try again in a moment."
        }
    }
}
