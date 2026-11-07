import Foundation

/// The order a Home Assistant camera's feeds are tried in, best first. A view
/// takes the first one that has not failed, so a camera falls back one step at a
/// time and never waits on a feed it cannot play.
///
/// - Full screen: WebRTC (low latency, sound, talk), then HLS (sound, a few
///   seconds behind), then MJPEG (any camera, no sound), then stills.
/// - Grid and faces: WebRTC without sound, then MJPEG, then stills. HLS starts
///   slowly and costs Home Assistant a stream worker per feed, so grids skip it.
/// - Still: stills only.
enum HACameraFeedPlan {
    /// - Parameters:
    ///   - capabilities: From `camera/capabilities`, or nil when Home Assistant did
    ///     not answer it (servers before 2024.11).
    ///   - supportsStream: The `stream` feature bit, the older sign of HLS.
    static func kinds(for purpose: CameraFeedPurpose, capabilities: HACameraCapabilities?,
                      supportsStream: Bool) -> [CameraFeedKind] {
        let webRTC = capabilities?.supportsWebRTC == true
        let hls = capabilities.map(\.supportsHLS) ?? supportsStream
        switch purpose {
        case .still:
            return [.stills]
        case .grid:
            return (webRTC ? [.webRTC] : []) + [.mjpeg, .stills]
        case .fullScreen:
            return (webRTC ? [.webRTC] : []) + (hls ? [.hls] : []) + [.mjpeg, .stills]
        }
    }

    /// The first kind that has not failed yet. Stills when every one has.
    static func next(for purpose: CameraFeedPurpose, capabilities: HACameraCapabilities?,
                     supportsStream: Bool, excluding failed: Set<CameraFeedKind>) -> CameraFeedKind {
        kinds(for: purpose, capabilities: capabilities, supportsStream: supportsStream)
            .first { !failed.contains($0) } ?? .stills
    }
}
