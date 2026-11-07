import Foundation
import HomePadCore
import Observation

/// Wake-up alarms: each person's list, when each rings next, and which ring now.
///
/// - Alarms persist across launches, with the next ring of each, so one that
///   came due while HomePad was closed still rings if it is less than
///   `ringWindow` late.
/// - At its time an alarm rings in the app (`AlarmRingingOverlay`) and posts
///   `.wake`. Stop sets up the next day it repeats, or turns a one-time alarm
///   off. Snooze rings again in nine minutes. An alarm nobody answers stops
///   after `ringWindow`.
/// - AlarmKit rings each alarm while HomePad is in the background
///   (`AlarmRingScheduling`). In the foreground the service rings first and
///   cancels the system alarm.
@MainActor
@Observable
public final class AlarmService {
    /// Every alarm, in the order they were added.
    public private(set) var alarms: [HomeAlarm]
    /// When each alarm that is on rings next.
    public private(set) var upcoming: [UUID: Date]
    /// Alarms whose next ring is the end of a snooze.
    private(set) var snoozed: Set<UUID>
    /// Alarms ringing now, with when each started.
    public private(set) var ringing: [UUID: Date] = [:]

    /// How long an alarm rings before it stops by itself, and how late one
    /// that came due while HomePad was closed may still ring.
    static let ringWindow: TimeInterval = 10 * 60

    @ObservationIgnored private let store: AlarmStateStore
    @ObservationIgnored private let events: EventBus?
    @ObservationIgnored private let rings: any AlarmRingScheduling
    @ObservationIgnored private let clock: () -> Date
    @ObservationIgnored private let calendar: Calendar
    /// The household's members, so alarms of someone who left are removed.
    @ObservationIgnored private let owners: (@MainActor () -> Set<UUID>)?
    @ObservationIgnored private var tickTask: Task<Void, Never>?
    /// What was last written to disk, so an unchanged minute writes nothing.
    @ObservationIgnored private var saved: AlarmState

    init(store: AlarmStateStore = AlarmStateStore(), events: EventBus?, rings: any AlarmRingScheduling,
         clock: @escaping () -> Date = Date.init, calendar: Calendar = .current, owners: (@MainActor () -> Set<UUID>)? = nil) {
        self.store = store
        self.events = events
        self.rings = rings
        self.clock = clock
        self.calendar = calendar
        self.owners = owners
        let state = store.load()
        alarms = state.alarms
        upcoming = state.upcoming
        snoozed = state.snoozed
        saved = state
        refresh()
    }

    // MARK: Reading

    /// A person's alarms by time of day, as in the Clock app.
    public func alarms(ownedBy ownerID: UUID) -> [HomeAlarm] {
        alarms.filter { $0.ownerID == ownerID }.sorted { ($0.hour, $0.minute) < ($1.hour, $1.minute) }
    }

    /// The person's alarm that rings soonest, and when.
    public func nextRing(ownedBy ownerID: UUID) -> (alarm: HomeAlarm, date: Date)? {
        alarms(ownedBy: ownerID)
            .compactMap { alarm in upcoming[alarm.id].map { (alarm: alarm, date: $0) } }
            .min { $0.date < $1.date }
    }

    /// Alarms ringing now, the first to start first.
    public var ringingAlarms: [HomeAlarm] {
        alarms.filter { ringing[$0.id] != nil }.sorted { ringing[$0.id]! < ringing[$1.id]! }
    }

    public func isSnoozed(_ id: UUID) -> Bool { snoozed.contains(id) }

    // MARK: Changing

    @discardableResult
    public func add(_ alarm: HomeAlarm) -> HomeAlarm {
        alarms.append(alarm)
        changed()
        return alarm
    }

    /// Saves an edited alarm. A new time or new days set its next ring afresh.
    public func update(_ alarm: HomeAlarm) {
        guard let index = index(of: alarm.id) else { return }
        alarms[index] = alarm
        clearNextRing(alarm.id)
        changed()
    }

    public func delete(_ id: UUID) {
        guard index(of: id) != nil else { return }
        alarms.removeAll { $0.id == id }
        ringing[id] = nil
        clearNextRing(id)
        changed()
    }

    public func setEnabled(_ id: UUID, _ isEnabled: Bool) {
        guard let index = index(of: id), alarms[index].isEnabled != isEnabled else { return }
        alarms[index].isEnabled = isEnabled
        if !isEnabled { ringing[id] = nil }
        clearNextRing(id)
        changed()
    }

    /// Stops a ringing alarm. It rings again on the next day it repeats, and a
    /// one-time alarm turns off.
    public func stop(_ id: UUID) {
        guard ringing[id] != nil else { return }
        finishRinging(id)
        changed()
    }

    /// Stops a ringing alarm and rings it again in nine minutes.
    public func snooze(_ id: UUID) {
        guard ringing[id] != nil, let alarm = alarm(id), alarm.allowsSnooze else { return stop(id) }
        ringing[id] = nil
        let end = clock().addingTimeInterval(HomeAlarm.snoozeLength)
        upcoming[id] = end
        snoozed.insert(id)
        rings.schedule(alarm, at: end)
        changed()
    }

    /// Keeps a person's alarms theirs under the ID the household knows them
    /// by, after this HomePad joined a household that already had them.
    public func moveOwner(from old: UUID, to new: UUID) {
        guard alarms.contains(where: { $0.ownerID == old }) else { return }
        for index in alarms.indices where alarms[index].ownerID == old {
            alarms[index].ownerID = new
        }
        changed()
    }

    /// Removes alarms whose owner left the household, so nothing rings that
    /// nobody can see or turn off. Does nothing while the household is empty.
    public func removeAlarms(keepingOwners memberIDs: Set<UUID>) {
        guard !memberIDs.isEmpty else { return }
        for alarm in alarms where !memberIDs.contains(alarm.ownerID) { delete(alarm.id) }
    }

    // MARK: Ringing

    /// Rings alarms whose time has come, stops those that rang for the whole
    /// window, sets the next ring of every alarm that is on, and removes
    /// alarms of people who left. Runs at each alarm's time, at least once a
    /// minute while an alarm is on, and when the app returns to the foreground.
    public func refresh() {
        if let owners { removeAlarms(keepingOwners: owners()) }
        let now = clock()
        for (id, start) in ringing where now.timeIntervalSince(start) >= Self.ringWindow {
            finishRinging(id)
        }
        var started = false
        for (id, date) in upcoming.sorted(by: { $0.value < $1.value }) where date <= now {
            upcoming[id] = nil
            snoozed.remove(id)
            if now.timeIntervalSince(date) < Self.ringWindow, !rings.wasDismissedOutsideApp(id) {
                ringing[id] = date
                rings.cancel(id)
                started = true
            } else {
                // Missed while the iPad was off, or rung and stopped outside the app.
                finishRinging(id)
            }
        }
        changed()
        if started { events?.post(.wake) }
    }

    #if DEBUG
    /// Rings an alarm now, for screenshots of the alert.
    func ringNow(_ id: UUID) {
        guard alarm(id) != nil else { return }
        upcoming[id] = clock()
        snoozed.remove(id)
        refresh()
    }
    #endif

    // MARK: Internals

    private func index(of id: UUID) -> Int? {
        alarms.firstIndex { $0.id == id }
    }

    private func alarm(_ id: UUID) -> HomeAlarm? {
        alarms.first { $0.id == id }
    }

    private func clearNextRing(_ id: UUID) {
        upcoming[id] = nil
        snoozed.remove(id)
        rings.cancel(id)
    }

    /// After a ring: a repeating alarm waits for its next day, a one-time one turns off.
    private func finishRinging(_ id: UUID) {
        ringing[id] = nil
        guard let index = index(of: id), !alarms[index].repeats else { return }
        alarms[index].isEnabled = false
        clearNextRing(id)
    }

    /// Gives every alarm that is on, not ringing and not snoozed its next
    /// ring, and takes it from those that are off.
    private func planNextRings() {
        let now = clock()
        for alarm in alarms {
            let id = alarm.id
            if !alarm.isEnabled {
                if upcoming[id] != nil { clearNextRing(id) }
                continue
            }
            guard ringing[id] == nil, !snoozed.contains(id) else { continue }
            // Due already: the next refresh rings it.
            if let current = upcoming[id], current <= now { continue }
            guard let next = alarm.nextOccurrence(after: now, calendar: calendar), upcoming[id] != next else { continue }
            upcoming[id] = next
            rings.schedule(alarm, at: next)
        }
        // Forget rings of alarms that are gone.
        for id in upcoming.keys where alarm(id) == nil { clearNextRing(id) }
    }

    private func changed() {
        planNextRings()
        let state = AlarmState(alarms: alarms, upcoming: upcoming, snoozed: snoozed)
        if state != saved {
            store.save(state)
            saved = state
        }
        ensureTicking()
    }

    /// Wakes at the next ring, or when a ringing alarm should stop by itself.
    /// At most a minute, so a change of the iPad's clock is noticed soon.
    private func ensureTicking() {
        tickTask?.cancel()
        tickTask = nil
        let stops = ringing.values.map { $0.addingTimeInterval(Self.ringWindow) }
        guard let soonest = (Array(upcoming.values) + stops).min() else { return }
        let wait = min(max(soonest.timeIntervalSince(clock()), 0), Self.longestWait)
        tickTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(wait))
            guard !Task.isCancelled, let self else { return }
            self.tickTask = nil
            self.refresh()
        }
    }

    private static let longestWait: TimeInterval = 60
}
