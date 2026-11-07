import HomePadCore
import SwiftUI
import WebRTC

/// A Home Assistant camera over WebRTC. A spinner shows until the first frame,
/// and over the last frame while a dropped stream reconnects. Calls `onFailure`
/// when the camera cannot play this way, so the feed view falls back.
struct WebRTCCameraView: View {
    @State private var session: WebRTCLiveSession
    private let audio: CameraAudioControl?
    private let onFailure: () -> Void
    @Environment(\.cameraContentMode) private var contentMode

    init(source: HAWebRTCSource, engine: WebRTCEngine, services: AppServices,
         audio: CameraAudioControl?, onFailure: @escaping () -> Void) {
        _session = State(initialValue: WebRTCLiveSession(source: source, engine: engine, services: services))
        self.audio = audio
        self.onFailure = onFailure
    }

    private struct SoundState: Equatable {
        var hasAudio: Bool
        var canTalk: Bool
        var isTalking: Bool
    }

    var body: some View {
        ZStack {
            WebRTCVideoSurface(session: session, contentMode: contentMode)
                .opacity(session.phase == .connecting ? 0 : 1)
            if session.phase != .live {
                CameraPlaceholder(message: nil, isLoading: true)
            }
        }
        .task { await session.run(onFallback: onFailure) }
        .onChange(of: audio?.isMuted ?? true, initial: true) { _, muted in
            session.isMuted = muted
        }
        .onChange(of: SoundState(hasAudio: session.hasAudio, canTalk: session.canTalk, isTalking: session.isTalking),
                  initial: true) { _, sound in
            guard let audio else { return }
            let current = session
            audio.update(owner: ObjectIdentifier(current), hasAudio: sound.hasAudio, canTalk: sound.canTalk,
                         isTalking: sound.isTalking) { [weak current] talking in
                try await current?.setTalking(talking)
            }
        }
        .onDisappear { audio?.release(owner: ObjectIdentifier(session)) }
    }
}

/// `RTCMTLVideoView` (Metal) for the session's video track. It keeps its last
/// frame when the track goes away, which holds the picture through a reconnect.
private struct WebRTCVideoSurface: UIViewRepresentable {
    let session: WebRTCLiveSession
    let contentMode: ContentMode

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> RTCMTLVideoView {
        let view = RTCMTLVideoView(frame: .zero)
        view.clipsToBounds = true
        view.videoContentMode = videoContentMode
        context.coordinator.session = session
        session.videoView = view
        return view
    }

    func updateUIView(_ view: RTCMTLVideoView, context: Context) {
        view.videoContentMode = videoContentMode
        if session.videoView !== view {
            context.coordinator.session = session
            session.videoView = view
        }
    }

    static func dismantleUIView(_ view: RTCMTLVideoView, coordinator: Coordinator) {
        if coordinator.session?.videoView === view { coordinator.session?.videoView = nil }
    }

    private var videoContentMode: UIView.ContentMode {
        contentMode == .fit ? .scaleAspectFit : .scaleAspectFill
    }

    @MainActor
    final class Coordinator {
        weak var session: WebRTCLiveSession?
    }
}
