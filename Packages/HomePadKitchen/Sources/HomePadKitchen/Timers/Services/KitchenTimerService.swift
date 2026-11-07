import Foundation
import HomePadCore
import Observation

/// HomePad's timer service. Replaces Core's in-memory one.
///
/// - Timers persist across launches (end dates are stored, so time keeps running).
/// - Several named timers run at once, each can pause, resume and take +1 minute.
/// - A finished timer posts `.timerFinished`, and the overlay rings in the app.
/// - AlarmKit rings for it when HomePad is in the background.
/// - A Live Activity and the Home Screen widget mirror running timers.
@MainActor
@Observable
public final class KitchenTimerService: TimerService {
    /// Every timer, in the order they were started.
    public private(set) var timers: [HomeTimer]

    /// Timers that ended longer ago than this while HomePad was closed are dropped
    /// at launch instead of ringing.
    static let staleAfter: TimeInterval = 60 * 60

    @ObservationIgnored private let store: TimerStateStore
    @ObservationIgnored private let events: EventBus?
    @ObservationIgnored private let alarms: any TimerAlarmScheduling
    @ObservationIgnored private let surfaces: any TimerSurfaceSyncing
    @ObservationIgnored private let clock: () -> Date
    @ObservationIgnored private var tickTask: Task<Void, Never>?

    public init(
        store: TimerStateStore = TimerStateStore(), events: EventBus?,
        alarms: any TimerAlarmScheduling, surfaces: any TimerSurfaceSyncing,
        clock: @escaping () -> Date = Date.init
    ) {
        self.store = store
        self.events = events
        self.alarms = alarms
        self.surfaces = surfaces
        self.clock = clock
        let now = clock()
        timers = store.load().filter { timer in
            guard timer.status != .paused, let end = timer.endDate else { return true }
            return now.timeIntervalSince(end) < Self.staleAfter
        }
        refresh()
        surfaces.sync(timers)
        ensureTicking()
    }

    // MARK: TimerService

    @discardableResult
    public func start(duration: TimeInterval, label: String) -> HomeTimer {
        let length = max(1, duration)
        let name = label.trimmingCharacters(in: .whitespacesAndNewlines)
        let timer = HomeTimer(label: name.isEmpty ? TimerFormat.defaultLabel(for: length) : name,
                              duration: length, status: .running, endDate: clock().addingTimeInterval(length))
        timers.append(timer)
        alarms.schedule(timer)
        changed()
        return timer
    }

    public func pause(_ id: HomeTimer.ID) {
        guard let index = index(of: id), timers[index].status == .running else { return }
        timers[index].remainingWhenPaused = timers[index].remaining(at: clock())
        timers[index].status = .paused
        timers[index].endDate = nil
        alarms.cancel(id)
        changed()
    }

    public func resume(_ id: HomeTimer.ID) {
        guard let index = index(of: id), timers[index].status == .paused else { return }
        timers[index].endDate = clock().addingTimeInterval(timers[index].remainingWhenPaused ?? timers[index].duration)
        timers[index].remainingWhenPaused = nil
        timers[index].status = .running
        alarms.schedule(timers[index])
        changed()
    }

    public func cancel(_ id: HomeTimer.ID) {
        guard index(of: id) != nil else { return }
        timers.removeAll { $0.id == id }
        alarms.cancel(id)
        changed()
    }

    public func add(_ seconds: TimeInterval, to id: HomeTimer.ID) {
        guard let index = index(of: id) else { return }
        switch timers[index].status {
        case .running:
            timers[index].endDate = timers[index].endDate?.addingTimeInterval(seconds)
        case .paused:
            timers[index].remainingWhenPaused = (timers[index].remainingWhenPaused ?? 0) + seconds
        case .finished:
            timers[index].status = .running
            timers[index].endDate = clock().addingTimeInterval(seconds)
            timers[index].duration = 0
        }
        timers[index].duration += seconds
        if timers[index].status == .running { alarms.schedule(timers[index]) }
        changed()
    }

    // MARK: Finishing

    /// Marks running timers whose time is up as finished and announces them.
    /// Runs when the soonest timer ends and when the app returns to the foreground.
    public func refresh() {
        let now = clock()
        var finished: [HomeTimer] = []
        var dismissed: [HomeTimer.ID] = []
        for index in timers.indices where timers[index].status == .running {
            guard let end = timers[index].endDate, end <= now else { continue }
            let id = timers[index].id
            if alarms.wasDismissedOutsideApp(id) {
                // It already rang in the background and someone stopped it there.
                dismissed.append(id)
            } else {
                timers[index].status = .finished
                alarms.cancel(id)
                finished.append(timers[index])
            }
        }
        guard !finished.isEmpty || !dismissed.isEmpty else { return }
        timers.removeAll { dismissed.contains($0.id) }
        changed()
        for timer in finished {
            events?.post(.timerFinished(id: timer.id, label: timer.label))
        }
    }

    // MARK: Internals

    private func index(of id: HomeTimer.ID) -> Int? {
        timers.firstIndex { $0.id == id }
    }

    private func changed() {
        store.save(timers)
        surfaces.sync(timers)
        ensureTicking()
    }

    /// Wakes when the soonest running timer ends, instead of checking four
    /// times a second for as long as any timer runs. Every change re-arms it,
    /// since a start, pause or +1 minute moves the soonest end.
    private func ensureTicking() {
        tickTask?.cancel()
        tickTask = nil
        guard let soonest = timers.filter({ $0.status == .running }).compactMap(\.endDate).min() else { return }
        // At most a minute, so a change of the iPad's clock is noticed soon.
        let wait = min(max(soonest.timeIntervalSince(clock()), 0), Self.longestWait)
        tickTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(wait))
            guard !Task.isCancelled, let self else { return }
            self.tickTask = nil
            self.refresh()
            if self.tickTask == nil { self.ensureTicking() }
        }
    }

    private static let longestWait: TimeInterval = 60
}
