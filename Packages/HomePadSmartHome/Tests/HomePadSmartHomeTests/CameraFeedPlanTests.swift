import Foundation
import Testing
@testable import HomePadSmartHome

/// The order Home Assistant cameras fall back through, for each kind of view.
@Suite("Camera feed fallback order")
struct CameraFeedPlanTests {
    private let both = HACameraCapabilities(streamTypes: ["hls", "web_rtc"], twoWayAudio: true)
    /// Nest and Ring: WebRTC from the integration itself, no HLS.
    private let nativeWebRTC = HACameraCapabilities(streamTypes: ["web_rtc"])

    @Test func fullScreenGoesWebRTCThenHLSThenMJPEGThenStills() {
        #expect(HACameraFeedPlan.kinds(for: .fullScreen, capabilities: both, supportsStream: true)
            == [.webRTC, .hls, .mjpeg, .stills])
        var failed: Set<CameraFeedKind> = []
        var order: [CameraFeedKind] = []
        for _ in 0..<5 {
            let next = HACameraFeedPlan.next(for: .fullScreen, capabilities: both, supportsStream: true, excluding: failed)
            order.append(next)
            failed.insert(next)
        }
        #expect(order == [.webRTC, .hls, .mjpeg, .stills, .stills], "stills stay once everything failed")
    }

    @Test func gridsSkipHLS() {
        #expect(HACameraFeedPlan.kinds(for: .grid, capabilities: both, supportsStream: true) == [.webRTC, .mjpeg, .stills])
    }

    @Test func nativeWebRTCHasNoHLS() {
        #expect(HACameraFeedPlan.kinds(for: .fullScreen, capabilities: nativeWebRTC, supportsStream: true)
            == [.webRTC, .mjpeg, .stills], "capabilities win over the stream bit")
    }

    @Test func olderServersFallBackOnTheStreamBit() {
        #expect(HACameraFeedPlan.kinds(for: .fullScreen, capabilities: nil, supportsStream: true) == [.hls, .mjpeg, .stills])
        #expect(HACameraFeedPlan.kinds(for: .fullScreen, capabilities: nil, supportsStream: false) == [.mjpeg, .stills])
        #expect(HACameraFeedPlan.kinds(for: .grid, capabilities: nil, supportsStream: true) == [.mjpeg, .stills])
    }

    @Test func stillsAreStills() {
        #expect(HACameraFeedPlan.kinds(for: .still, capabilities: both, supportsStream: true) == [.stills])
    }

    @Test func feedsNameTheirKind() {
        let request = URLRequest(url: URL(string: "http://ha.test:8123/api/camera_proxy_stream/camera.front_door")!)
        #expect(CameraFeed.mjpeg(request).kind == .mjpeg)
        #expect(CameraFeed.hls(URL(string: "http://ha.test:8123/api/hls/a/master_playlist.m3u8")!).kind == .hls)
        #expect(CameraFeed.stills(every: .seconds(10)).kind == .stills)
        #expect(CameraFeed.unavailable("Gone").kind == nil, "nothing to fall back from")
    }
}
