import Foundation

/// What the iPad is doing, as the host of background work reports it: the
/// shell, once a second while HomePad is on screen, and iOS's launches while
/// it is in the background.
public struct BackgroundEnvironment: Equatable, Sendable {
    /// HomePad is on screen. In the background the display is not HomePad's,
    /// so the display conditions count as met.
    public var isForeground: Bool
    public var display: DisplayCondition
    /// Charging or full.
    public var isOnPower: Bool
    /// An app is zooming open or closed, or a touch has just landed.
    public var isInteracting: Bool
    /// Hot enough that optional work should pause.
    public var isOverheating: Bool

    public init(isForeground: Bool, display: DisplayCondition, isOnPower: Bool, isInteracting: Bool, isOverheating: Bool) {
        self.isForeground = isForeground
        self.display = display
        self.isOnPower = isOnPower
        self.isInteracting = isInteracting
        self.isOverheating = isOverheating
    }

    /// Before any host reported: nothing may start.
    public static let unknown = BackgroundEnvironment(isForeground: true, display: .active, isOnPower: false,
                                                      isInteracting: true, isOverheating: false)

    /// In the background during a system launch, on power or not.
    public static func systemLaunch(isOnPower: Bool) -> BackgroundEnvironment {
        BackgroundEnvironment(isForeground: false, display: .sleeping, isOnPower: isOnPower,
                              isInteracting: false, isOverheating: false)
    }
}

/// What a task last did, kept across launches.
public struct BackgroundTaskRecord: Codable, Equatable, Sendable {
    /// When its last run started.
    public var lastRun: Date?
    /// When that run ended. Nil while it runs.
    public var lastFinished: Date?
    public var outcome: BackgroundTaskOutcome?
    /// Why a module asked for a run that has not started yet.
    public var request: String?

    public init(lastRun: Date? = nil, lastFinished: Date? = nil, outcome: BackgroundTaskOutcome? = nil, request: String? = nil) {
        self.lastRun = lastRun
        self.lastFinished = lastFinished
        self.outcome = outcome
        self.request = request
    }
}

/// Why a task that is due has not started.
public enum BackgroundBlocker: Equatable, Sendable {
    case interacting
    case overheating
    case displayInUse
    case displayAwake
    case onBattery

    /// "Waiting for ..." in Settings.
    public var waitingFor: String {
        switch self {
        case .interacting: "the screen to settle"
        case .overheating: "the iPad to cool down"
        case .displayInUse: "nobody to be using the screen"
        case .displayAwake: "the screen to sleep"
        case .onBattery: "power"
        }
    }
}

/// The scheduling rules, pure so they are tested without clocks or the shell.
public enum BackgroundSchedule {
    /// When a task should run next. Now when a module asked, when it never
    /// ran or when its last run stopped part way. Otherwise its last run
    /// plus its interval, or plus its retry interval after a failure.
    public static func nextRun(_ record: BackgroundTaskRecord, interval: TimeInterval, retryInterval: TimeInterval?,
                               now: Date) -> Date {
        guard record.request == nil, let lastRun = record.lastRun else { return now }
        switch record.outcome {
        case .stopped: return now
        case .failed: return lastRun.addingTimeInterval(min(retryInterval ?? interval, interval))
        case .done, .skipped, nil: return lastRun.addingTimeInterval(interval)
        }
    }

    public static func isDue(_ record: BackgroundTaskRecord, interval: TimeInterval, retryInterval: TimeInterval?,
                             now: Date) -> Bool {
        nextRun(record, interval: interval, retryInterval: retryInterval, now: now) <= now
    }

    /// What keeps a task from starting now, nil when it may. Every task waits
    /// while an app zooms or a touch has just landed, and while the iPad is
    /// hot. Then come its own conditions.
    public static func blocker(_ conditions: BackgroundConditions, in environment: BackgroundEnvironment) -> BackgroundBlocker? {
        if environment.isInteracting { return .interacting }
        if environment.isOverheating { return .overheating }
        return conditionBlocker(conditions, in: environment)
    }

    /// The task's own condition that does not hold, nil when they all do.
    /// In the background the display is not HomePad's, so only power counts.
    public static func conditionBlocker(_ conditions: BackgroundConditions, in environment: BackgroundEnvironment) -> BackgroundBlocker? {
        if environment.isForeground {
            if conditions.contains(.displayIdle), environment.display == .active { return .displayInUse }
            if conditions.contains(.displayAsleep), environment.display != .sleeping { return .displayAwake }
        }
        if conditions.contains(.onPower), !environment.isOnPower { return .onBattery }
        return nil
    }

    /// The task to start among those that are due and not blocked: the one
    /// whose run is the most overdue, so none waits behind another forever.
    public static func nextTask(_ candidates: [(id: String, nextRun: Date, isBlocked: Bool)], now: Date) -> String? {
        candidates
            .filter { !$0.isBlocked && $0.nextRun <= now }
            .min { $0.nextRun < $1.nextRun }?
            .id
    }
}
