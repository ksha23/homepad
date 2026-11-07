import Foundation
import HomePadCore

// The HomePad's side of the `calendar.*` and `reminders.*` messages inside a visit.
extension PhoneCalendarsClient {
    func registerHandlers() {
        let link = visits.link
        link.on(.calendarOffer) { [weak self] message, peer in
            guard let offer = try? message.content(CalendarShareOffer.self) else { return }
            self?.receive(offer, from: peer)
        }
        link.on(.calendarReply) { [weak self] message, peer in
            guard let reply = try? message.content(CalendarReply.self) else { return }
            self?.visits.deliver(message, answering: reply.requestID, from: peer)
        }
        link.on(.remindersReply) { [weak self] message, peer in
            guard let reply = try? message.content(RemindersReply.self) else { return }
            self?.visits.deliver(message, answering: reply.requestID, from: peer)
        }
        link.on(.calendarChanged) { [weak self] message, peer in
            guard let changed = try? message.content(CalendarChanged.self) else { return }
            self?.visits.deliver(message, answering: changed.changeID, from: peer)
        }
        link.on(.remindersChanged) { [weak self] message, peer in
            guard let changed = try? message.content(RemindersChanged.self) else { return }
            self?.visits.deliver(message, answering: changed.changeID, from: peer)
        }
    }

    // MARK: Offers

    /// A linked phone says which calendars and lists it shares. What it no
    /// longer shares leaves this iPad at once, and what it newly shares is
    /// fetched if its owner is here.
    func receive(_ offer: CalendarShareOffer, from peer: PeerDevice) {
        guard peer.kind.isCompanion, let device = visits.approver.store.device(peer.id) else { return }
        let calendarIDs = Set(offer.calendarIDs), listIDs = Set(offer.listIDs)
        var sharing: Set<PhoneDataKind> = []
        if !calendarIDs.isEmpty { sharing.insert(.calendars) }
        if !listIDs.isEmpty { sharing.insert(.reminders) }
        var known: Set<String> = []
        if let state, state.visit.memberID == device.memberID {
            known = Set(state.index.calendars.map(\.id) + state.index.lists.map(\.id))
            state.index.narrow(toCalendars: calendarIDs, lists: listIDs)
            save(state)
            publish(state.visit)
        } else {
            let cache = cache
            cacheQueue.sync {
                guard var index = cache.load(member: device.memberID) else { return }
                index.narrow(toCalendars: calendarIDs, lists: listIDs)
                cache.save(index, member: device.memberID)
            }
        }
        visits.receiveOffer(from: peer, sharing: sharing, of: kinds, wakeTag: sharing.isEmpty ? nil : offer.wakeTag)
        // A calendar or list turned on while its owner is here shows without waiting for the next visit.
        guard let visit = visits.visit(of: device.memberID), visit.hasFetched,
              !calendarIDs.union(listIDs).subtracting(known).isEmpty else { return }
        Task { await refresh(visit) }
    }

    // MARK: Fetching

    /// Fetches again during a visit, after its first fetch.
    func refresh(_ visit: PhoneVisit) async {
        guard await visits.open(visit) else { return }
        await prefetch(visit)
        visits.closeIfIdle(visit)
    }

    /// The shared calendars and their events from the past week to six weeks ahead.
    func fetchCalendars(_ visit: PhoneVisit) async {
        let window = PhoneCalendarsPolicy.window(around: visits.now(), calendar: calendar)
        let request = CalendarRequest(start: window.start, end: window.end, pendingChanges: pending(.calendars, in: visit))
        guard let message = await visits.request(.calendarRequest, request, id: request.id, in: visit),
              let reply = try? message.content(CalendarReply.self), let state = current(visit) else { return }
        settle(reply.savedChanges, in: state)
        state.index.deviceName = visit.deviceName
        state.index.calendars = reply.calendars
        state.index.events = reply.events
        state.index.window = window
        state.index.calendarsFetchedAt = visits.now()
        publish(visit)
    }

    /// The shared lists, their open reminders and those checked off this past week.
    func fetchReminders(_ visit: PhoneVisit) async {
        let since = calendar.date(byAdding: .day, value: -PhoneCalendarsPolicy.completedDays, to: visits.now()) ?? visits.now()
        let request = RemindersRequest(completedSince: since, pendingChanges: pending(.reminders, in: visit))
        guard let message = await visits.request(.remindersRequest, request, id: request.id, in: visit),
              let reply = try? message.content(RemindersReply.self), let state = current(visit) else { return }
        settle(reply.savedChanges, in: state)
        state.index.deviceName = visit.deviceName
        state.index.lists = reply.lists
        state.index.reminders = reply.reminders
        state.index.remindersFetchedAt = visits.now()
        publish(visit)
    }

    /// The changes of one kind still waiting, for the phone to say which it saved.
    private func pending(_ kind: PhoneDataKind, in visit: PhoneVisit) -> [UUID]? {
        let ids = current(visit)?.outbox.filter { $0.kind == kind }.map(\.id) ?? []
        return ids.isEmpty ? nil : ids
    }

    /// Drops the changes the phone says it saved already: what it just sent shows them.
    private func settle(_ saved: [UUID]?, in state: CalendarVisitState) {
        guard let saved, !saved.isEmpty else { return }
        state.outbox.removeAll { saved.contains($0.id) && !state.inFlight.contains($0.id) }
    }

    // MARK: Changes

    /// Sends the changes that wait for the phone, one at a time and in
    /// order, waking the phone if needed. A phone that cannot be reached
    /// leaves them waiting for the next time it is.
    func sendOutbox(_ visit: PhoneVisit) async {
        guard let state = current(visit), !state.isSending else { return }
        state.isSending = true
        defer { state.isSending = false }
        while current(visit) === state, let write = state.outbox.first(where: { $0.state != .failed }) {
            mark(write.id, .sending, nil, in: state)
            guard await visits.open(visit), current(visit) === state else {
                markUnsent(.waiting, "\(visit.deviceName) isn't reachable. HomePad sends this when it is.", in: state)
                return
            }
            guard visit.grantedKinds.contains(write.kind) else {
                mark(write.id, .failed, Self.wording(.notShared, phone: visit.deviceName, kind: write.kind), in: state)
                continue
            }
            state.inFlight.insert(write.id)
            let answer = await send(write, in: visit)
            state.inFlight.remove(write.id)
            guard current(visit) === state else { return }
            switch answer {
            case .saved(let apply):
                apply(&state.index)
                state.outbox.removeAll { $0.id == write.id }
                save(state)
                publish(visit)
            case .refused(let failure):
                mark(write.id, .failed, Self.wording(failure, phone: visit.deviceName, kind: write.kind), in: state)
            case .noAnswer:
                // The phone may have saved it and the answer got lost. It saves
                // each change ID once, so sending it again is safe.
                markUnsent(.waiting, "\(visit.deviceName) didn't answer. HomePad tries again when it is back.", in: state)
                visits.closeIfIdle(visit)
                return
            }
        }
        visits.closeIfIdle(visit)
    }

    private enum Answer {
        case saved((inout PhoneCalendarsIndex) -> Void)
        case refused(PhoneChangeFailure?)
        case noAnswer
    }

    /// One change to the phone and its answer.
    private func send(_ write: PhoneCalendarWrite, in visit: PhoneVisit) async -> Answer {
        if let change = write.event {
            guard let message = await visits.request(.calendarChange, change, id: write.id, in: visit, timeout: changeTimeout),
                  let changed = try? message.content(CalendarChanged.self) else { return .noAnswer }
            guard let event = changed.event else { return .refused(changed.failure.flatMap(PhoneChangeFailure.init(rawValue:))) }
            let replaced = write.eventID
            return .saved { index in
                index.events.removeAll { $0.id == replaced || $0.id == event.id }
                index.events.append(event)
            }
        }
        guard let change = write.reminder,
              let message = await visits.request(.remindersChange, change, id: write.id, in: visit, timeout: changeTimeout),
              let changed = try? message.content(RemindersChanged.self) else { return .noAnswer }
        guard let reminder = changed.reminder else { return .refused(changed.failure.flatMap(PhoneChangeFailure.init(rawValue:))) }
        return .saved { index in
            index.reminders.removeAll { $0.id == reminder.id }
            index.reminders.append(reminder)
        }
    }

    private func mark(_ writeID: UUID, _ newState: PhoneWriteStatus.State, _ message: String?, in state: CalendarVisitState) {
        guard let at = state.outbox.firstIndex(where: { $0.id == writeID }) else { return }
        guard state.outbox[at].state != newState || state.outbox[at].message != message else { return }
        state.outbox[at].state = newState
        state.outbox[at].message = message
        save(state)
        publish(state.visit)
    }

    /// Every change not failed and not saved waits, with the reason.
    private func markUnsent(_ newState: PhoneWriteStatus.State, _ message: String, in state: CalendarVisitState) {
        for write in state.outbox where write.state != .failed {
            mark(write.id, newState, message, in: state)
        }
    }

    /// Why the phone could not save a change, in words.
    static func wording(_ failure: PhoneChangeFailure?, phone: String, kind: PhoneDataKind) -> String {
        let thing = kind == .calendars ? "calendar" : "list"
        switch failure {
        case .notFound: return "It is no longer on \(phone)."
        case .readOnly: return "That \(thing) is read-only on \(phone)."
        case .notShared: return "\(phone) no longer shares that \(thing) here."
        case .noAccess: return "HomePad on \(phone) has no access to \(kind == .calendars ? "Calendar" : "Reminders")."
        case .saveFailed, nil: return "\(phone) couldn't save it."
        }
    }
}
