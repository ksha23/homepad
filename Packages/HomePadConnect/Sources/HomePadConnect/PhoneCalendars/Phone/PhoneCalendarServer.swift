import Foundation
import HomePadCore
import Observation

/// On an iPhone: serves the calendars and reminders lists its owner checked
/// for each HomePad, and saves the changes made there, to nothing else. Two
/// kinds of data a visit carries (`PhoneVisitServer`), which opens the
/// session and checks the grant.
///
/// A HomePad sees only the calendars and lists the person checked for it,
/// and every change it sends must stay inside them: an event's own calendar
/// and the one it moves to, a reminder's list. Each change is saved once by
/// its ID, so one sent again after a lost answer is not added twice.
@MainActor
@Observable
public final class PhoneCalendarServer: PhoneVisitServing {
    /// Why sharing could not change, by HomePad ID.
    public private(set) var errors: [String: String] = [:]
    /// When this phone last sent calendars or saved a change for each HomePad, by HomePad ID.
    public private(set) var lastServed: [String: Date] = [:]
    /// What this phone shares with each HomePad, by HomePad ID.
    public private(set) var sharing: [String: CalendarSharingChoice]
    /// The phone's own calendars and lists, for choosing. Empty without access.
    public private(set) var calendars: [PhoneCalendar] = []
    public private(set) var lists: [PhoneCalendar] = []

    let kinds: Set<PhoneDataKind> = [.calendars, .reminders]
    @ObservationIgnored let visit: PhoneVisitServer
    @ObservationIgnored var store: any PhoneCalendarStore
    /// Changes already saved, newest last, so one sent again gets the same answer.
    @ObservationIgnored private var applied: [AppliedChange]
    @ObservationIgnored private let log = Log.make("PhoneCalendars")

    static let sharingKey = SettingKey<[String: CalendarSharingChoice]>("connect.calendars.sharing", default: [:])
    static let appliedKey = SettingKey<[AppliedChange]>("connect.calendars.applied", default: [])
    /// Changes remembered. A HomePad sends a change again within a visit or two.
    static let appliedLimit = 200
    /// The longest span of events one request may ask for.
    static let longestSpan: TimeInterval = 400 * 86_400

    init(visit: PhoneVisitServer) {
        self.visit = visit
        self.sharing = visit.services.settings[Self.sharingKey]
        self.applied = visit.services.settings[Self.appliedKey]
        self.store = EventKitPhoneCalendars()
        #if DEBUG
        if UserDefaults.standard.bool(forKey: "ConnectPhoneCalendarsDemo") { store = DemoPhoneCalendars() }
        #endif
    }

    func start() {
        let link = visit.link
        link.on(.calendarRequest) { [weak self] message, peer in
            guard let request = try? message.content(CalendarRequest.self) else { return }
            self?.serve(request, to: peer)
        }
        link.on(.remindersRequest) { [weak self] message, peer in
            guard let request = try? message.content(RemindersRequest.self) else { return }
            Task { await self?.serve(request, to: peer) }
        }
        link.on(.calendarChange) { [weak self] message, peer in
            guard let change = try? message.content(CalendarChange.self) else { return }
            self?.apply(change, from: peer)
        }
        link.on(.remindersChange) { [weak self] message, peer in
            guard let change = try? message.content(RemindersChange.self) else { return }
            self?.apply(change, from: peer)
        }
        store.onChange = { [weak self] in self?.reload() }
        reload()
    }

    // MARK: Choosing

    public var hasEventAccess: Bool { store.hasEventAccess }
    public var hasReminderAccess: Bool { store.hasReminderAccess }
    public var isEventAccessDenied: Bool { store.isEventAccessDenied }
    public var isReminderAccessDenied: Bool { store.isReminderAccessDenied }

    /// Reads the phone's calendars and lists again, and forgets choices of
    /// ones that are gone.
    public func reload() {
        calendars = store.calendars()
        lists = store.lists()
        var pruned = sharing
        for (homePadID, choice) in sharing {
            var kept = choice
            if store.hasEventAccess { kept.calendarIDs.formIntersection(calendars.map(\.id)) }
            if store.hasReminderAccess { kept.listIDs.formIntersection(lists.map(\.id)) }
            pruned[homePadID] = kept.isEmpty ? nil : kept
        }
        guard pruned != sharing else { return }
        let changed = Set(sharing.keys).union(pruned.keys).filter { sharing[$0] != pruned[$0] }
        sharing = pruned
        persist()
        Task { for homePadID in changed { await visit.sharingChanged(self, with: homePadID) } }
    }

    /// Asks for full access to Calendar or Reminders, after the person tapped to choose.
    func requestAccess(to kind: PhoneDataKind, for homePadID: String) async {
        errors[homePadID] = nil
        let granted = kind == .reminders ? await store.requestReminderAccess() : await store.requestEventAccess()
        if !granted {
            let app = kind == .reminders ? "Reminders" : "Calendars"
            errors[homePadID] = "Allow HomePad full access in Settings, Privacy & Security, \(app)."
        }
        reload()
    }

    /// True when that calendar or list is shared with that HomePad.
    public func isShared(_ id: String, with homePadID: String) -> Bool {
        guard let choice = sharing[homePadID] else { return false }
        return choice.calendarIDs.contains(id) || choice.listIDs.contains(id)
    }

    /// Shares one calendar or list with a HomePad, or stops. The HomePad
    /// drops what it saved of one turned off at once.
    func setShared(_ isOn: Bool, _ item: PhoneCalendar, kind: PhoneDataKind, with homePadID: String) async {
        errors[homePadID] = nil
        if isOn, visit.linkedMember(on: homePadID) == nil {
            errors[homePadID] = "Link this iPhone to yourself on that HomePad first."
            return
        }
        var choice = sharing[homePadID] ?? CalendarSharingChoice(wakeTag: visit.wakeTag(for: homePadID))
        switch (kind, isOn) {
        case (.reminders, true): choice.listIDs.insert(item.id)
        case (.reminders, false): choice.listIDs.remove(item.id)
        case (_, true): choice.calendarIDs.insert(item.id)
        case (_, false): choice.calendarIDs.remove(item.id)
        }
        sharing[homePadID] = choice.isEmpty ? nil : choice
        persist()
        await visit.sharingChanged(self, with: homePadID)
    }

    /// Bluetooth's state for the card, nil while nothing is shared.
    public var wakeProblem: String? { visit.wakeProblem }

    // MARK: PhoneVisitServing

    func sharedKinds(with homePadID: String) -> Set<PhoneDataKind> {
        guard let choice = sharing[homePadID] else { return [] }
        var kinds: Set<PhoneDataKind> = []
        if !choice.calendarIDs.isEmpty { kinds.insert(.calendars) }
        if !choice.listIDs.isEmpty { kinds.insert(.reminders) }
        return kinds
    }

    var readableKinds: Set<PhoneDataKind> {
        var kinds: Set<PhoneDataKind> = []
        if store.hasEventAccess { kinds.insert(.calendars) }
        if store.hasReminderAccess { kinds.insert(.reminders) }
        return kinds
    }

    func wakeTag(for homePadID: String) -> Data? { sharing[homePadID]?.wakeTag }

    var wakeTags: [Data] { sharing.values.map(\.wakeTag) }

    /// Sent even when nothing is shared, so a HomePad that missed the change
    /// while this phone was away drops what it saved.
    func sendOffer(to homePadID: String) async {
        let choice = sharing[homePadID]
        let offer = CalendarShareOffer(calendarIDs: (choice?.calendarIDs ?? []).sorted(), listIDs: (choice?.listIDs ?? []).sorted(),
                                       wakeTag: choice?.wakeTag)
        await visit.sendOffer(.calendarOffer, offer, to: homePadID)
    }

    func stopSharing(with homePadID: String) {
        guard sharing[homePadID] != nil else { return }
        sharing[homePadID] = nil
        persist()
    }

    // MARK: Reading

    func serve(_ request: CalendarRequest, to peer: PeerDevice) {
        guard visit.grantedMember(peer, for: .calendars) != nil, let choice = sharing[peer.id] else { return }
        lastServed[peer.id] = visit.now()
        let shared = store.calendars().filter { choice.calendarIDs.contains($0.id) }
        let end = min(request.end, request.start.addingTimeInterval(Self.longestSpan))
        let events = Array(store.events(in: Set(shared.map(\.id)), from: request.start, to: end).prefix(PhoneCalendarsPolicy.eventLimit))
        visit.send(.calendarReply, CalendarReply(requestID: request.id, calendars: shared, events: events,
                                                 savedChanges: saved(request.pendingChanges)), to: peer)
    }

    /// The changes among `pending` this phone has saved.
    private func saved(_ pending: [UUID]?) -> [UUID]? {
        guard let pending, !pending.isEmpty else { return nil }
        let done = Set(applied.map(\.id))
        return pending.filter(done.contains)
    }

    func serve(_ request: RemindersRequest, to peer: PeerDevice) async {
        guard visit.grantedMember(peer, for: .reminders) != nil, let choice = sharing[peer.id] else { return }
        lastServed[peer.id] = visit.now()
        let shared = store.lists().filter { choice.listIDs.contains($0.id) }
        let reminders = await store.reminders(in: Set(shared.map(\.id)), completedSince: request.completedSince)
        // The session may have closed while EventKit read.
        guard visit.grantedMember(peer, for: .reminders) != nil else { return }
        visit.send(.remindersReply, RemindersReply(requestID: request.id, lists: shared,
                                                   reminders: Array(reminders.prefix(PhoneCalendarsPolicy.reminderLimit)),
                                                   savedChanges: saved(request.pendingChanges)), to: peer)
    }

    // MARK: Changes

    func apply(_ change: CalendarChange, from peer: PeerDevice) {
        guard visit.grantedMember(peer, for: .calendars) != nil else { return }
        let allowed = sharing[peer.id]?.calendarIDs ?? []
        lastServed[peer.id] = visit.now()
        if let done = applied.first(where: { $0.id == change.id }) {
            let event = done.start.flatMap { store.event(itemID: done.itemID, start: $0) }
            visit.send(.calendarChanged, CalendarChanged(changeID: change.id, event: event, failure: event == nil ? .notFound : nil), to: peer)
            return
        }
        do {
            let event: PhoneEvent
            if let itemID = change.itemID, let start = change.occurrenceStart {
                event = try store.updateEvent(itemID: itemID, occurrenceStart: start, with: change.fields, allowed: allowed)
            } else {
                event = try store.addEvent(change.fields, allowed: allowed)
            }
            remember(AppliedChange(id: change.id, itemID: event.itemID, start: event.start))
            log.info("Saved an event from \(peer.name, privacy: .public)")
            visit.send(.calendarChanged, CalendarChanged(changeID: change.id, event: event), to: peer)
        } catch {
            let failure = error as? PhoneChangeFailure ?? .saveFailed
            log.info("Did not save an event from \(peer.name, privacy: .public): \(failure.rawValue, privacy: .public)")
            visit.send(.calendarChanged, CalendarChanged(changeID: change.id, failure: failure), to: peer)
        }
    }

    func apply(_ change: RemindersChange, from peer: PeerDevice) {
        guard visit.grantedMember(peer, for: .reminders) != nil else { return }
        let allowed = sharing[peer.id]?.listIDs ?? []
        lastServed[peer.id] = visit.now()
        if let done = applied.first(where: { $0.id == change.id }) {
            let reminder = store.reminder(done.itemID)
            visit.send(.remindersChanged, RemindersChanged(changeID: change.id, reminder: reminder,
                                                           failure: reminder == nil ? .notFound : nil), to: peer)
            return
        }
        do {
            let reminder: PhoneReminder
            if let add = change.add {
                reminder = try store.addReminder(add, allowed: allowed)
            } else if let id = change.reminderID, let completed = change.completed {
                reminder = try store.setCompleted(id, completed: completed, allowed: allowed)
            } else {
                throw PhoneChangeFailure.saveFailed
            }
            remember(AppliedChange(id: change.id, itemID: reminder.id, start: nil))
            visit.send(.remindersChanged, RemindersChanged(changeID: change.id, reminder: reminder), to: peer)
        } catch {
            let failure = error as? PhoneChangeFailure ?? .saveFailed
            log.info("Did not save a reminder from \(peer.name, privacy: .public): \(failure.rawValue, privacy: .public)")
            visit.send(.remindersChanged, RemindersChanged(changeID: change.id, failure: failure), to: peer)
        }
    }

    private func remember(_ change: AppliedChange) {
        applied.append(change)
        if applied.count > Self.appliedLimit { applied.removeFirst(applied.count - Self.appliedLimit) }
        visit.services.settings[Self.appliedKey] = applied
    }

    private func persist() {
        visit.services.settings[Self.sharingKey] = sharing
    }
}

/// On a phone: the calendars and lists shared with one HomePad.
public struct CalendarSharingChoice: Codable, Equatable, Sendable {
    /// Written over Bluetooth to that HomePad, so it can wake this phone.
    /// The same tag Show My Photos uses for that HomePad.
    public var wakeTag: Data
    public var calendarIDs: Set<String> = []
    public var listIDs: Set<String> = []

    var isEmpty: Bool { calendarIDs.isEmpty && listIDs.isEmpty }
}

/// A change this phone saved: its ID and what it saved, to answer it again.
struct AppliedChange: Codable, Equatable, Sendable {
    var id: UUID
    var itemID: String
    /// An event occurrence's start, nil for reminders.
    var start: Date?
}
