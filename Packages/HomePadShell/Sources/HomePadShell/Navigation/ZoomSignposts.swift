import os

/// Marks the app zoom in Instruments' Points of Interest, so a trace shows what the main thread does
/// around each one: an event where an open, a close, a swipe or a swipe's spring back starts, and one
/// where the window lands. Signposts cost next to nothing while nothing records them.
enum ZoomSignposts {
    private static let signposter = OSSignposter(subsystem: "com.ksha23.homepad", category: .pointsOfInterest)

    /// What happened to the window.
    enum Event {
        case open, close, swipe, springBack, land
    }

    static func note(_ event: Event) {
        switch event {
        case .open: signposter.emitEvent("Zoom open")
        case .close: signposter.emitEvent("Zoom close")
        case .swipe: signposter.emitEvent("Zoom swipe")
        case .springBack: signposter.emitEvent("Zoom spring back")
        case .land: signposter.emitEvent("Zoom land")
        }
    }
}
