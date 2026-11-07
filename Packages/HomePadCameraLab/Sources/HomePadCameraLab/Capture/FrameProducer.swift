import Foundation

/// Status of the shared camera feed, shown in tool UIs.
enum FeedStatus: Equatable, Sendable {
    case stopped
    case starting
    case running
    /// Another app or the system took the camera (Split View, a call).
    case interrupted(String)
    case failed(String)
}

/// Something that produces frames into a `FrameHub`: the real camera or the demo feed.
@MainActor
protocol FrameProducer: AnyObject {
    var hub: FrameHub { get }
    var position: CameraPosition? { get }
    var isDemo: Bool { get }
    /// Called on the main actor whenever the feed status changes.
    var onStatusChange: ((FeedStatus) -> Void)? { get set }

    func start(position: CameraPosition)
    func stop()
}
