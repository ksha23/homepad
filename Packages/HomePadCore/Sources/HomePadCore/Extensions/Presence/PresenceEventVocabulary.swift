import Foundation

/// Labels the Presence module posts in `HomePadEvent.soundDetected(label:confidence:)`.
/// Compare against these instead of string literals.
public enum SoundEventLabel {
    /// Smoke detector. Apple's classifier has no separate carbon monoxide label,
    /// so CO alarms most likely arrive as this label too.
    public static let smokeAlarm = "smoke_alarm"
    public static let doorbell = "doorbell"
    public static let knock = "knock"
    public static let dogBark = "dog_bark"
    public static let babyCrying = "baby_crying"
    public static let glassBreaking = "glass_breaking"
    public static let siren = "siren"
}

/// Requests other modules can send to the Presence module through the event bus,
/// since modules never import each other.
///
///     services.events.post(.listenForHeadGestures(seconds: 8))   // before "Unlock the front door?"
public enum PresenceRequest {
    /// `.custom` name for "listen for an AirPods nod or shake now". Payload: seconds as a number.
    public static let listenForHeadGestures = "presence.listenForHeadGestures"
}

public extension HomePadEvent {
    /// Asks Presence to listen for AirPods head gestures for a while. Answers arrive
    /// as `.headGesture(.nod)` or `.headGesture(.shake)`. No-op without headphones.
    static func listenForHeadGestures(seconds: Double = 8) -> HomePadEvent {
        .custom(name: PresenceRequest.listenForHeadGestures, payload: .number(seconds))
    }
}
