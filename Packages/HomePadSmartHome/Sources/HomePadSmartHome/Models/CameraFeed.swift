import Foundation
@preconcurrency import HomeKit
import HomePadCore

/// How a camera view will be used, so each backend can pick the cheapest feed that looks right.
enum CameraFeedPurpose: Sendable {
    /// One cell of the camera grid, or a face's feed. Low latency, modest quality, no sound.
    case grid
    /// Full-screen single camera or the doorbell overlay. Best quality, audio when available.
    case fullScreen
    /// A still image that refreshes now and then (widgets, thumbnails).
    case still
}

/// The kinds of feed a view can fall back through. A view that cannot play one
/// asks again without it (see `CameraFeedView`).
enum CameraFeedKind: Hashable, Sendable {
    case webRTC, hls, mjpeg, stills
}

/// The concrete source a camera view renders.
enum CameraFeed {
    /// HomeKit live video through `HMCameraView`.
    case homeKitStream(HMCameraProfile)
    /// The most recent HomeKit snapshot through `HMCameraView`.
    case homeKitSnapshot(HMCameraProfile)
    /// Home Assistant's WebRTC signaling (`camera/webrtc/offer`): low latency, with sound.
    case webRTC(HAWebRTCSource)
    /// An HLS playlist for AVPlayer (Home Assistant `camera/stream`).
    case hls(URL)
    /// A multipart MJPEG stream (Home Assistant `camera_proxy_stream`).
    case mjpeg(URLRequest)
    /// Periodically refreshed JPEG stills from `SmartHomeService.snapshot(cameraID:)`.
    case stills(every: Duration)
    /// The animated demo scene.
    case demo(HomeCamera)
    case unavailable(String)

    /// The kind to leave out when this feed cannot play. Nil for feeds with no fallback.
    var kind: CameraFeedKind? {
        switch self {
        case .webRTC: .webRTC
        case .hls: .hls
        case .mjpeg: .mjpeg
        case .stills: .stills
        case .homeKitStream, .homeKitSnapshot, .demo, .unavailable: nil
        }
    }
}

/// What a WebRTC view needs to start a session with Home Assistant.
struct HAWebRTCSource {
    let entityID: String
    /// Receive the camera's sound (full screen). Grids ask for video alone, so
    /// go2rtc never transcodes audio nobody hears.
    let receivesAudio: Bool
    /// Offer to send sound as well, for hold to talk. Only when Home Assistant
    /// reports two-way audio for the camera.
    let offersTalk: Bool
    let transport: any HAWebRTCTransport
}
