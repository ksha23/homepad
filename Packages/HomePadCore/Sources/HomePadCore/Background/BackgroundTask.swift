import Foundation

/// What a background task waits for before it starts, besides its time.
public struct BackgroundConditions: OptionSet, Hashable, Sendable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }

    /// Nobody is using the screen: the display shows the face, is dimmed, red
    /// for the night or asleep. A task with it stops at its next checkpoint
    /// when someone starts using the screen, and runs again later.
    public static let displayIdle = BackgroundConditions(rawValue: 1 << 0)
    /// The screen sleeps (nobody has been around for a while).
    public static let displayAsleep = BackgroundConditions(rawValue: 1 << 1)
    /// The iPad is charging or full.
    public static let onPower = BackgroundConditions(rawValue: 1 << 2)
}

/// The launches iOS may give HomePad while it is in the background
/// (`BGTaskScheduler`), which a task may run in.
public struct SystemBackgroundLaunches: OptionSet, Hashable, Sendable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }

    /// A short app refresh (about 30 seconds), as often as iOS allows.
    public static let appRefresh = SystemBackgroundLaunches(rawValue: 1 << 0)
    /// A longer processing launch, usually at night on power.
    public static let processing = SystemBackgroundLaunches(rawValue: 1 << 1)
}

/// How a run of a background task ended, in words for Settings.
public enum BackgroundTaskOutcome: Codable, Equatable, Sendable {
    /// It did its work, with what it did ("12 albums, 40 thumbnails ready").
    case done(String)
    /// It had nothing it could do, with why ("Photos access is off").
    case skipped(String)
    case failed(String)
    /// It stopped part way, for example because someone started using the
    /// screen. It runs again as soon as its conditions allow.
    case stopped(String)

    /// The words under the result in Settings.
    public var detail: String {
        switch self {
        case .done(let text), .skipped(let text), .failed(let text), .stopped(let text): text
        }
    }

    /// One word for the result.
    public var title: String {
        switch self {
        case .done: "Done"
        case .skipped: "Skipped"
        case .failed: "Failed"
        case .stopped: "Stopped"
        }
    }
}

/// Why a background task is running.
public enum BackgroundTrigger: Equatable, Sendable {
    /// Its time came.
    case schedule
    /// A module asked for a run, for example because the photo library changed.
    case request(String)
    /// Someone tapped Run Now in Settings, which skips its conditions.
    case runNow
    /// iOS launched HomePad in the background for it.
    case system
}

/// Work a module wants done while HomePad runs and nobody needs the screen,
/// and while it is in the background when iOS allows. Register it with
/// `AppServices.backgroundWork.register(_:)` during `register`:
///
///     services.backgroundWork.register(BackgroundTaskDescriptor(
///         id: "personal.photoSync", title: "Photo Sync",
///         summary: "Reads new photos and prepares their thumbnails.",
///         interval: { 3600 }, conditions: .displayIdle, systemLaunches: [.appRefresh, .processing],
///         prepare: { photos.startSyncing() }
///     ) { context in
///         await photos.sync(context)
///     })
///
/// The shell runs one task at a time, never while an app zooms or right after
/// a touch, on the main actor at low priority. Put the heavy part of a run
/// off the main actor at `BackgroundWork.priority`, and call
/// `context.checkpoint()` between steps, so a long run waits for the screen
/// and stops when asked.
public struct BackgroundTaskDescriptor: Identifiable {
    public let id: String
    public let title: String
    /// One sentence about what it does, for Settings.
    public let summary: String
    /// Seconds from one run to the next, read each time so a setting can change it.
    public let interval: @MainActor () -> TimeInterval
    /// Seconds to wait after a failed run, when sooner than `interval`.
    public let retryInterval: TimeInterval?
    public let conditions: BackgroundConditions
    public let systemLaunches: SystemBackgroundLaunches
    /// Runs once when background work starts on the iPad that shows HomePad,
    /// for something long-lived such as a change observer. Never on the
    /// iPhone and Mac companions.
    public let prepare: (@MainActor () -> Void)?
    public let run: @MainActor (BackgroundTaskContext) async -> BackgroundTaskOutcome

    public init(
        id: String, title: String, summary: String, interval: @escaping @MainActor () -> TimeInterval,
        retryInterval: TimeInterval? = nil, conditions: BackgroundConditions = [],
        systemLaunches: SystemBackgroundLaunches = [], prepare: (@MainActor () -> Void)? = nil,
        run: @escaping @MainActor (BackgroundTaskContext) async -> BackgroundTaskOutcome
    ) {
        self.id = id
        self.title = title
        self.summary = summary
        self.interval = interval
        self.retryInterval = retryInterval
        self.conditions = conditions
        self.systemLaunches = systemLaunches
        self.prepare = prepare
        self.run = run
    }
}

/// Handed to a running task, to wait for the screen between steps and to
/// notice when it should stop.
@MainActor
public final class BackgroundTaskContext {
    public let trigger: BackgroundTrigger
    /// The time a system launch gave ran out, or the run was cancelled.
    public private(set) var isExpired = false
    private weak var work: BackgroundWork?
    private let conditions: BackgroundConditions

    init(trigger: BackgroundTrigger, conditions: BackgroundConditions, work: BackgroundWork) {
        self.trigger = trigger
        self.conditions = conditions
        self.work = work
    }

    /// Call between steps. Waits while an app zooms, a touch has just landed
    /// or the iPad is hot, then returns false when the run should stop: its
    /// time ran out, or one of its conditions stopped holding, such as
    /// someone using a screen it waits to be idle. Run Now skips conditions.
    public func checkpoint() async -> Bool {
        while let work, !isExpired, !Task.isCancelled {
            let environment = work.environment
            if trigger != .runNow, BackgroundSchedule.conditionBlocker(conditions, in: environment) != nil {
                return false
            }
            guard environment.isInteracting || environment.isOverheating else { return true }
            await work.waitForQuiet()
        }
        return false
    }

    func expire() {
        isExpired = true
    }
}
