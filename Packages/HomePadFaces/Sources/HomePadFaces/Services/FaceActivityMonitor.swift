import Foundation
import HomePadCore
import Observation

/// Household events faces react to.
enum FaceActivity: String, Codable, CaseIterable, Sendable {
    case doorbell
    case motion
    case timerFinished

    var title: String {
        switch self {
        case .doorbell: "Doorbell Rings"
        case .motion: "Motion Detected"
        case .timerFinished: "Timer Finishes"
        }
    }
}

/// Listens to the event bus once for every face and remembers when things
/// happened, so Smart Rotation, Flow and Critters can react without each
/// subscribing on their own.
@MainActor
@Observable
final class FaceActivityMonitor {
    /// When each kind of activity last happened.
    private(set) var lastSeen: [FaceActivity: Date] = [:]
    /// Increments on every motion event. Flow pulses when it changes.
    private(set) var motionPulse = 0
    /// Label of the most recent finished timer.
    private(set) var lastTimerLabel: String?
    /// Camera that rang most recently.
    private(set) var lastDoorbellCameraID: String?

    @ObservationIgnored private var task: Task<Void, Never>?

    init() {}

    /// Starts listening. Safe to call more than once.
    func start(events: EventBus) {
        guard task == nil else { return }
        let stream = events.stream()
        task = Task { [weak self] in
            for await event in stream {
                self?.handle(event)
            }
        }
    }

    /// Records an event. Internal so tests and previews can feed events directly.
    func handle(_ event: HomePadEvent, at date: Date = Date()) {
        switch event {
        case .doorbellRang(let cameraID):
            lastSeen[.doorbell] = date
            lastDoorbellCameraID = cameraID
        case .motionDetected:
            lastSeen[.motion] = date
            motionPulse += 1
        case .timerFinished(_, let label):
            lastSeen[.timerFinished] = date
            lastTimerLabel = label
        default:
            break
        }
    }

    /// True when an activity happened within a window before `now`.
    func happened(_ activity: FaceActivity, within window: TimeInterval, now: Date = Date()) -> Bool {
        guard let date = lastSeen[activity] else { return false }
        return now.timeIntervalSince(date) <= window && date <= now.addingTimeInterval(1)
    }
}
