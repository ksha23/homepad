import Foundation
import Observation

/// Things that happen which other modules may want to react to.
/// Add cases sparingly. Prefer `.custom` for module-private signals.
public enum HomePadEvent: Sendable {
    // Smart home
    case doorbellRang(cameraID: String)
    case accessoryAlert(accessoryID: String, message: String)

    // Sensing
    case presenceChanged(PresenceSnapshot)
    case memberRecognized(UUID)
    case gesture(HandGesture)
    case headGesture(HeadGesture)
    /// A recognized sound such as "smoke_alarm", "doorbell", "dog_bark", "baby_crying".
    case soundDetected(label: String, confidence: Double)
    case motionDetected(source: String)

    // Time
    case timerFinished(id: UUID, label: String)

    // Communication
    case intercomReceived(from: String, text: String?)
    case handoffReceived(activityType: String, payload: JSONValue)

    // Navigation requests (any module may ask the shell to show something)
    case openApp(id: String)
    case showFace(id: String)
    case invokeAssistant(prompt: String?)
    case wake                       // leave ambient or sleeping mode
    case goAmbient                  // return to the face

    case custom(name: String, payload: JSONValue)
}

/// A tiny broadcast bus. Every subscriber gets every event posted after it subscribed.
///
///     for await event in services.events.stream() { ... }
@MainActor
@Observable
public final class EventBus {
    @ObservationIgnored private var continuations: [UUID: AsyncStream<HomePadEvent>.Continuation] = [:]
    /// Most recent events, newest last, for debugging screens.
    public private(set) var recent: [(Date, HomePadEvent)] = []

    public init() {}

    public func post(_ event: HomePadEvent) {
        recent.append((Date(), event))
        if recent.count > 100 { recent.removeFirst(recent.count - 100) }
        for continuation in continuations.values {
            continuation.yield(event)
        }
    }

    public func stream() -> AsyncStream<HomePadEvent> {
        let id = UUID()
        return AsyncStream { continuation in
            continuations[id] = continuation
            continuation.onTermination = { [weak self] _ in
                Task { @MainActor in self?.continuations[id] = nil }
            }
        }
    }
}
