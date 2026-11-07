import HomePadCore
import HomePadUI
import SwiftUI

/// Any camera from any backend in its frame: cropped to fill for grids and
/// stills, shown whole for full screen. Asks the service for the best feed for
/// the purpose (grid, full screen or still) and renders it. A feed that cannot
/// play is left out and the service asks for the next one, so a Home Assistant
/// camera falls from WebRTC to HLS, MJPEG and stills (`HACameraFeedPlan`) behind
/// one spinner.
///
/// Nothing streams where motion cannot be seen. A thumbnail (face and widget
/// pickers) shows one still that does not refresh. A face frosted behind the
/// Home Screen shows refreshing stills instead of video. A feed covered by
/// another camera screen or the doorbell shows one still. While the display
/// sleeps or HomePad is in the background nothing plays, refreshes or
/// downloads, and the feed starts again when it can be seen.
struct CameraFeedView: View {
    @Environment(UnifiedSmartHomeService.self) private var service
    @Environment(AppServices.self) private var services
    @Environment(DoorbellPresenter.self) private var doorbell: DoorbellPresenter?
    @Environment(\.isThumbnail) private var isThumbnail
    @Environment(\.isFrosted) private var isFrosted
    @Environment(\.displayCondition) private var displayCondition
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.cameraFeedsCovered) private var isCoveredByCamera
    @Environment(\.isDoorbellScreen) private var isDoorbellScreen
    let camera: HomeCamera
    var purpose: CameraFeedPurpose = .grid
    /// The screen's sound control. Nil keeps the feed silent.
    var audio: CameraAudioControl?

    @State private var feed: CameraFeed?
    /// Kinds that failed for one request. A new request starts with none.
    @State private var failures = Failures()

    private var isAsleep: Bool { displayCondition == .sleeping || scenePhase == .background }

    /// Something else fills the screen over this feed.
    private var isCovered: Bool {
        isCoveredByCamera || (doorbell?.ring != nil && !isDoorbellScreen)
    }

    /// The feed to ask for: stills where video cannot be seen.
    private var activePurpose: CameraFeedPurpose { isThumbnail || isFrosted || isCovered ? .still : purpose }

    /// Home Assistant ends its streams with the WebSocket, so its feeds start over
    /// on each new connection, WebRTC first again.
    private var connectionEpoch: Int {
        camera.backend == .homeAssistant ? service.homeAssistant.connectionEpoch : 0
    }

    private struct Request: Hashable {
        var cameraID: HomeCamera.ID
        var purpose: CameraFeedPurpose
        var isAsleep: Bool
        var connectionEpoch: Int
    }

    private struct Failures: Equatable {
        var request: Request?
        var kinds: Set<CameraFeedKind> = []
    }

    private struct Attempt: Equatable {
        var request: Request
        var excluding: Set<CameraFeedKind>
    }

    private var request: Request {
        Request(cameraID: camera.id, purpose: activePurpose, isAsleep: isAsleep, connectionEpoch: connectionEpoch)
    }

    private var excluded: Set<CameraFeedKind> {
        failures.request == request ? failures.kinds : []
    }

    var body: some View {
        ZStack {
            Color.black
            if !isAsleep { content }
        }
        .environment(\.cameraContentMode, purpose == .fullScreen ? .fit : .fill)
        // Video sits on black in every appearance, so its placeholder text is light.
        .environment(\.colorScheme, .dark)
        .clipped()
        .task(id: Attempt(request: request, excluding: excluded)) {
            // Dropping the feed tears its player down, and waking asks for a fresh one.
            feed = nil
            guard !isAsleep else { return }
            feed = await service.feed(for: camera.id, purpose: activePurpose, excluding: excluded)
        }
    }

    /// Leaves out the kind that could not play, which asks for the next one.
    private func fail(_ feed: CameraFeed) {
        guard let kind = feed.kind else { return }
        failures = Failures(request: request, kinds: excluded.union([kind]))
    }

    @ViewBuilder
    private var content: some View {
        switch feed {
        case nil:
            CameraPlaceholder(message: nil, isLoading: true)
        case .homeKitStream(let profile):
            HomeKitLiveCameraView(profile: profile, hub: service.homeKit.streams)
        case .homeKitSnapshot(let profile):
            HomeKitSnapshotCameraView(profile: profile, refreshes: !isThumbnail && !isCovered)
        case .webRTC(let source):
            if let engine = service.webRTC {
                WebRTCCameraView(source: source, engine: engine, services: services, audio: audio) { fail(.webRTC(source)) }
            } else {
                Color.clear.onAppear { fail(.webRTC(source)) }
            }
        case .hls(let url):
            HLSPlayerView(url: url, audio: audio) { fail(.hls(url)) }
        case .mjpeg(let request):
            MJPEGStreamView(request: request, maximumFramesPerSecond: purpose == .grid ? 8 : 20) { fail(.mjpeg(request)) }
        case .stills(let interval):
            StillCameraView(cameraID: camera.id, interval: interval, refreshes: !isThumbnail && !isCovered)
        case .demo(let camera):
            // Video ticks every second. Stills are snapshots, as on a real camera.
            if activePurpose == .still {
                DemoStillView(camera: camera, refreshes: !isThumbnail && !isCovered)
            } else {
                DemoCameraFeedView(camera: camera)
            }
        case .unavailable(let message):
            CameraPlaceholder(message: message, isLoading: false)
        }
    }
}

extension EnvironmentValues {
    /// True on camera feeds that a camera screen covers (the Home app's grid under
    /// a full-screen camera), so they hold one still instead of streaming.
    @Entry var cameraFeedsCovered = false
    /// True inside the doorbell screen, the one feed that keeps playing while it shows.
    @Entry var isDoorbellScreen = false
}
