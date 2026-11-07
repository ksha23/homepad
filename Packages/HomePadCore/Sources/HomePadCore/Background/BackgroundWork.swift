import Foundation
import Observation

/// Background work: tasks modules register, which HomePad runs while it is on
/// screen and nobody needs it, and in the launches iOS gives it in the
/// background. HomePad runs as a kiosk all day, so most of its background work
/// happens while the app is in front but the screen is idle.
///
/// Modules register tasks in `register` (`register(_:)`) and ask for an early
/// run when something changed (`requestRun(_:reason:)`). Nothing runs until
/// a host starts it: the shell does on the iPad that shows HomePad
/// (`start()`), and reports what the iPad is doing every second
/// (`update(_:)`), so the companions on iPhone and Mac never run any.
///
/// One task runs at a time. A due task starts once nothing blocks it
/// (`BackgroundSchedule.blocker`), the most overdue first.
@MainActor
@Observable
public final class BackgroundWork {
    /// The priority for a run and for the heavy part of it, below anything a
    /// person waits for.
    public static let priority: TaskPriority = .utility

    public private(set) var tasks: [BackgroundTaskDescriptor] = []
    /// What each task last did, by ID.
    public private(set) var records: [String: BackgroundTaskRecord] = [:]
    /// The task running now.
    public private(set) var runningID: String?
    /// What the host last reported. Nothing may start until it reports.
    public private(set) var environment = BackgroundEnvironment.unknown
    /// True once the host started background work on this device.
    public private(set) var isStarted = false

    @ObservationIgnored private var current: (task: Task<Void, Never>, context: BackgroundTaskContext)?
    /// Tasks someone tapped Run Now for while another task ran.
    @ObservationIgnored private var pendingRunNow: [String] = []
    @ObservationIgnored private var prepared: Set<String> = []
    /// Runs waiting at a checkpoint for the screen to settle.
    @ObservationIgnored private var quietWaiters: [CheckedContinuation<Void, Never>] = []
    /// True while a launch from iOS runs tasks, so a late report from the shell does not change its environment.
    @ObservationIgnored var isInSystemLaunch = false
    @ObservationIgnored private let store: BackgroundRecordStore
    @ObservationIgnored let clock: () -> Date
    @ObservationIgnored let log = Log.make("Background")

    /// - Parameters:
    ///   - recordsURL: Where records are kept across launches. Nil keeps them in memory (tests).
    ///   - clock: The current time, injectable for tests.
    public init(recordsURL: URL? = BackgroundRecordStore.defaultURL, clock: @escaping () -> Date = Date.init) {
        self.store = BackgroundRecordStore(url: recordsURL)
        self.clock = clock
        self.records = store.load()
    }

    // MARK: Registering

    /// Adds a task, or replaces one with the same ID.
    public func register(_ task: BackgroundTaskDescriptor) {
        tasks.removeAll { $0.id == task.id }
        tasks.append(task)
        if isStarted { prepare(task) }
    }

    public func task(_ id: String) -> BackgroundTaskDescriptor? {
        tasks.first { $0.id == id }
    }

    public func record(for id: String) -> BackgroundTaskRecord {
        records[id] ?? BackgroundTaskRecord()
    }

    // MARK: The host

    /// Starts background work on this device: each task's `prepare` runs
    /// once, and due tasks start from the next `update(_:)`.
    public func start() {
        guard !isStarted else { return }
        isStarted = true
        tasks.forEach(prepare)
    }

    /// What the iPad is doing now. Starts the next due task when nothing blocks it.
    public func update(_ environment: BackgroundEnvironment) {
        guard !isInSystemLaunch else { return }
        apply(environment)
        guard isStarted, runningID == nil else { return }
        startNextDue()
    }

    // MARK: Asking for runs

    /// Asks for a run as soon as the task's conditions allow, for example
    /// after a change it should catch up with. It starts at the next report.
    public func requestRun(_ id: String, reason: String) {
        guard task(id) != nil else { return }
        records[id, default: BackgroundTaskRecord()].request = reason
    }

    /// Runs a task now, skipping its time and its conditions, as Settings'
    /// Run Now does. It still waits for an app zoom or a touch at its
    /// checkpoints, and for a task already running.
    public func runNow(_ id: String) {
        guard task(id) != nil, id != runningID, !pendingRunNow.contains(id) else { return }
        if runningID == nil {
            start(id, trigger: .runNow)
        } else {
            pendingRunNow.append(id)
        }
    }

    /// True while Run Now waits for another task to finish.
    public func isWaitingToRunNow(_ id: String) -> Bool {
        pendingRunNow.contains(id)
    }

    // MARK: When

    /// When a task runs next, if nothing blocks it then.
    public func nextRun(for id: String) -> Date? {
        guard let task = task(id) else { return nil }
        return BackgroundSchedule.nextRun(record(for: id), interval: task.interval(), retryInterval: task.retryInterval, now: clock())
    }

    /// What keeps a due task from starting right now, nil when nothing does.
    public func blocker(for id: String) -> BackgroundBlocker? {
        guard let task = task(id) else { return nil }
        return BackgroundSchedule.blocker(task.conditions, in: environment)
    }

    // MARK: Running

    func apply(_ environment: BackgroundEnvironment) {
        if environment != self.environment { self.environment = environment }
        if !environment.isInteracting, !environment.isOverheating { resumeWaiters() }
    }

    private func prepare(_ task: BackgroundTaskDescriptor) {
        guard prepared.insert(task.id).inserted else { return }
        task.prepare?()
    }

    /// The task that should start now, if any. During a launch from iOS, only
    /// tasks that run in that kind of launch.
    func nextDueTask(allowing launch: SystemBackgroundLaunches? = nil) -> String? {
        let now = clock()
        let candidates = tasks
            .filter { task in launch.map { !task.systemLaunches.isDisjoint(with: $0) } ?? true }
            .map { task in
                (id: task.id,
                 nextRun: BackgroundSchedule.nextRun(record(for: task.id), interval: task.interval(),
                                                     retryInterval: task.retryInterval, now: now),
                 isBlocked: BackgroundSchedule.blocker(task.conditions, in: environment) != nil)
            }
        return BackgroundSchedule.nextTask(candidates, now: now)
    }

    private func startNextDue() {
        guard let id = nextDueTask() else { return }
        let reason = record(for: id).request
        start(id, trigger: reason.map(BackgroundTrigger.request) ?? .schedule)
    }

    /// Starts one run and returns the task that runs it.
    @discardableResult
    func start(_ id: String, trigger: BackgroundTrigger) -> Task<Void, Never>? {
        guard let descriptor = task(id), runningID == nil else { return nil }
        let context = BackgroundTaskContext(trigger: trigger, conditions: descriptor.conditions, work: self)
        var record = record(for: id)
        record.lastRun = clock()
        record.lastFinished = nil
        record.request = nil
        records[id] = record
        runningID = id
        log.info("Starting \(id, privacy: .public)")
        let run = Task(priority: Self.priority) { [weak self] in
            let outcome = await descriptor.run(context)
            self?.finish(id, outcome: outcome)
        }
        current = (run, context)
        return run
    }

    private func finish(_ id: String, outcome: BackgroundTaskOutcome) {
        var record = record(for: id)
        record.lastFinished = clock()
        record.outcome = outcome
        records[id] = record
        runningID = nil
        current = nil
        log.info("Finished \(id, privacy: .public): \(outcome.title, privacy: .public)")
        store.save(records)
        if !pendingRunNow.isEmpty, !isInSystemLaunch {
            start(pendingRunNow.removeFirst(), trigger: .runNow)
        }
    }

    /// Ends the run in progress at its next checkpoint, when iOS's time for
    /// a background launch runs out.
    func expireCurrentRun() {
        current?.context.expire()
        current?.task.cancel()
        resumeWaiters()
    }

    /// Waits until the screen settles (no zoom, no touch just landed) and the iPad is not hot.
    func waitForQuiet() async {
        await withCheckedContinuation { quietWaiters.append($0) }
    }

    private func resumeWaiters() {
        guard !quietWaiters.isEmpty else { return }
        let waiters = quietWaiters
        quietWaiters = []
        waiters.forEach { $0.resume() }
    }
}

/// Keeps task records in a small JSON file in Application Support, so Settings
/// shows the last run after a relaunch and a task's time carries over. Not a
/// setting: writing settings redraws every view that reads one.
public struct BackgroundRecordStore: Sendable {
    let url: URL?

    /// Application Support/BackgroundWork/records.json.
    public static var defaultURL: URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("BackgroundWork", isDirectory: true)
            .appendingPathComponent("records.json")
    }

    func load() -> [String: BackgroundTaskRecord] {
        guard let url, let data = try? Data(contentsOf: url),
              let records = try? JSONDecoder().decode([String: BackgroundTaskRecord].self, from: data) else { return [:] }
        return records
    }

    /// Writes off the main thread.
    func save(_ records: [String: BackgroundTaskRecord]) {
        guard let url, let data = try? JSONEncoder().encode(records) else { return }
        Task.detached(priority: .utility) {
            try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? data.write(to: url, options: .atomic)
        }
    }
}
