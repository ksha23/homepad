import AVFoundation
import HomePadCore
import Observation
import WebRTC

/// One camera view's WebRTC stream from Home Assistant, from the first offer to
/// teardown. `run()` lives as long as the view's task: cancelling it (the view
/// leaving, the app going to the background, the display sleeping) closes the
/// peer connection and Home Assistant's session at once.
///
/// A stream that never shows a frame falls back (`onFallback`), so the view moves
/// on to HLS or MJPEG. A stream that played and then drops (Wi-Fi changes, Home
/// Assistant restarts) starts a new session, keeping the last frame on screen.
@MainActor
@Observable
final class WebRTCLiveSession {
    enum Phase: Equatable {
        case connecting, live, reconnecting
    }

    private(set) var phase: Phase = .connecting
    /// The camera sends sound on this session.
    private(set) var hasAudio = false
    /// The camera takes sound on this session: the hold to talk button can show.
    private(set) var canTalk = false
    private(set) var isTalking = false
    var isMuted = true {
        didSet { applyAudio() }
    }

    @ObservationIgnored let source: HAWebRTCSource
    @ObservationIgnored private let engine: WebRTCEngine
    @ObservationIgnored private let services: AppServices
    @ObservationIgnored private var peer: WebRTCPeerConnection?
    @ObservationIgnored private var negotiation: HAWebRTCNegotiation?
    @ObservationIgnored private var frameWatcher: FirstFrameWatcher?
    @ObservationIgnored private var attemptEvents: AsyncStream<AttemptEvent>.Continuation?
    @ObservationIgnored private var talkRequested = false
    @ObservationIgnored private let log = Log.make("CameraWebRTC")

    /// From the offer to the first frame. go2rtc answers once the camera's stream
    /// opens, and the first frame waits for a keyframe, a few seconds even for
    /// cloud cameras. Past this the path will not play, and HLS gets its turn.
    static let startTimeout: Duration = .seconds(10)
    /// ICE reports disconnected after a couple of missed checks and often comes
    /// back by itself on a Wi-Fi blip. Longer than this, a new session is faster.
    static let disconnectGrace: Duration = .seconds(4)
    /// Waits between new sessions after a drop, growing while they keep failing.
    static let restartDelays: [Duration] = [.seconds(1), .seconds(2), .seconds(4), .seconds(8), .seconds(15)]

    private static let talkOwner = "smarthome.camera.talk"

    /// The view the video draws into. The current session's track renders to it.
    @ObservationIgnored weak var videoView: RTCMTLVideoView? {
        didSet {
            guard oldValue !== videoView, let track = peer?.videoTrack else { return }
            if let oldValue { track.remove(oldValue) }
            if let videoView { track.add(videoView) }
        }
    }

    init(source: HAWebRTCSource, engine: WebRTCEngine, services: AppServices) {
        self.source = source
        self.engine = engine
        self.services = services
    }

    // MARK: Running

    private enum AttemptEvent: Sendable {
        case state(WebRTCConnectionState)
        case firstFrame
        case sessionEnded
        case disconnectedTooLong
        case timedOut
    }

    private enum Outcome {
        case cancelled
        /// No frame ever showed. `refused` when Home Assistant said no.
        case neverPlayed(refused: Bool)
        case dropped
    }

    /// Plays until cancelled. Calls `onFallback` when this camera cannot play over WebRTC.
    func run(onFallback: @escaping () -> Void) async {
        var offersTalk = source.offersTalk
        var hasPlayed = false
        var failures = 0
        while !Task.isCancelled {
            phase = hasPlayed ? .reconnecting : .connecting
            switch await attempt(offersTalk: offersTalk) {
            case .cancelled:
                return
            case .neverPlayed(let refused):
                // A camera that cannot take sound may refuse the whole offer, so ask again for video and sound only.
                if refused, offersTalk {
                    offersTalk = false
                    log.info("\(self.source.entityID, privacy: .public) refused talk, retrying without it")
                    continue
                }
                guard hasPlayed else {
                    log.info("\(self.source.entityID, privacy: .public) did not play over WebRTC, falling back")
                    onFallback()
                    return
                }
                failures += 1
            case .dropped:
                hasPlayed = true
                failures = 0
                log.info("\(self.source.entityID, privacy: .public) dropped, starting a new session")
            }
            let delay = Self.restartDelays[min(failures, Self.restartDelays.count - 1)]
            try? await Task.sleep(for: delay)
        }
    }

    /// One peer connection, from the offer until it ends.
    private func attempt(offersTalk: Bool) async -> Outcome {
        let transport = source.transport
        let entityID = source.entityID
        let config: HAWebRTCClientConfig
        do {
            config = HAWebRTCClientConfig(json: try await transport.send(HARequests.webRTCClientConfig(entityID)))
        } catch {
            return Task.isCancelled ? .cancelled : .neverPlayed(refused: false)
        }
        guard !Task.isCancelled else { return .cancelled }
        let media = WebRTCPeerConnection.Media(receivesAudio: source.receivesAudio, offersTalk: offersTalk)
        guard let peer = WebRTCPeerConnection(factory: engine.factory, config: config, media: media) else {
            return .neverPlayed(refused: false)
        }
        let negotiation = HAWebRTCNegotiation(entityID: entityID, transport: transport, peer: peer)
        let (events, continuation) = AsyncStream.makeStream(of: AttemptEvent.self)
        let watcher = FirstFrameWatcher { continuation.yield(.firstFrame) }
        self.peer = peer
        self.negotiation = negotiation
        frameWatcher = watcher
        attemptEvents = continuation
        defer { endAttempt() }
        negotiation.onSessionError = { _ in continuation.yield(.sessionEnded) }
        if let track = peer.videoTrack {
            track.add(watcher)
            if let videoView { track.add(videoView) }
        }
        let forwarder = Task { [weak negotiation] in
            for await event in peer.events {
                switch event {
                case .localCandidate(let candidate): negotiation?.addLocalCandidate(candidate)
                case .state(let state): continuation.yield(.state(state))
                }
            }
        }
        // Stopping the negotiation ends a wait for the answer, which then counts as not refused.
        let deadline = Task { [weak negotiation] in
            try? await Task.sleep(for: Self.startTimeout)
            guard !Task.isCancelled else { return }
            negotiation?.stop()
            continuation.yield(.timedOut)
        }
        defer {
            forwarder.cancel()
            deadline.cancel()
        }

        do {
            let answer = SDPMedia(sdp: try await negotiation.start())
            hasAudio = source.receivesAudio && answer.hasAudio
            canTalk = offersTalk && answer.acceptsAudio
            applyAudio()
        } catch {
            if Task.isCancelled { return .cancelled }
            switch error as? HAWebRTCNegotiation.Failure {
            case .refused, .homeAssistant: return .neverPlayed(refused: true)
            default: return .neverPlayed(refused: false)
            }
        }

        var hasPlayed = false
        var grace: Task<Void, Never>?
        defer { grace?.cancel() }
        for await event in events {
            switch event {
            case .firstFrame:
                guard !hasPlayed else { continue }
                hasPlayed = true
                deadline.cancel()
                phase = .live
                applyAudio()
            case .state(.connected):
                grace?.cancel()
                grace = nil
            case .state(.disconnected):
                guard grace == nil else { continue }
                grace = Task {
                    try? await Task.sleep(for: Self.disconnectGrace)
                    guard !Task.isCancelled else { return }
                    continuation.yield(.disconnectedTooLong)
                }
            case .state(.failed), .state(.closed), .sessionEnded, .disconnectedTooLong:
                return hasPlayed ? .dropped : .neverPlayed(refused: false)
            case .timedOut:
                if !hasPlayed { return .neverPlayed(refused: false) }
            case .state(.new), .state(.connecting):
                continue
            }
        }
        return .cancelled
    }

    /// Closes the peer connection and Home Assistant's session.
    private func endAttempt() {
        stopTalking()
        if let track = peer?.videoTrack {
            if let frameWatcher { track.remove(frameWatcher) }
            if let videoView { track.remove(videoView) }
        }
        negotiation?.stop()
        peer?.close()
        attemptEvents?.finish()
        negotiation = nil
        peer = nil
        frameWatcher = nil
        attemptEvents = nil
        hasAudio = false
        canTalk = false
        applyAudio()
    }

    // MARK: Sound and talk

    /// Camera sound plays while unmuted, live, and nobody is talking. Talking
    /// mutes it, since there is no echo canceller on this path and the door
    /// would hear itself.
    private func applyAudio() {
        let audible = hasAudio && !isMuted && !isTalking && phase == .live
        peer?.audioTrack?.isEnabled = audible
        engine.audioDevice.setAudible(audible, owner: ObjectIdentifier(self))
    }

    enum TalkError: LocalizedError {
        case microphoneOff, permissionDenied

        var errorDescription: String? {
            switch self {
            case .microphoneOff: "The microphone is turned off in Control Center."
            case .permissionDenied: "HomePad needs the microphone to talk through the camera. You can allow it in the iPad's Settings app."
            }
        }
    }

    /// Starts sending the microphone while a finger holds Talk, and stops on release.
    func setTalking(_ talking: Bool) async throws {
        talkRequested = talking
        guard talking else {
            stopTalking()
            return
        }
        guard canTalk, !isTalking else { return }
        guard services.settings[CoreSettings.microphoneEnabled] else { throw TalkError.microphoneOff }
        guard await AVAudioApplication.requestRecordPermission() else { throw TalkError.permissionDenied }
        // Let go while the permission was asked for, or the session ended meanwhile.
        guard talkRequested, canTalk, let peer else { return }
        // Like a spoken request, talk gets the microphone now, even over AirPlay music.
        services.audioSession.claim(.voice, owner: Self.talkOwner)
        peer.setSending(true)
        isTalking = true
        applyAudio()
    }

    private func stopTalking() {
        talkRequested = false
        guard isTalking else { return }
        peer?.setSending(false)
        services.audioSession.release(owner: Self.talkOwner)
        isTalking = false
        applyAudio()
    }

    /// Marks the session's first decoded frame. RTCMTLVideoView reports a size
    /// only when it changes, so a new session after a drop would never hear it.
    private final class FirstFrameWatcher: NSObject, RTCVideoRenderer, @unchecked Sendable {
        private let onFirstFrame: @Sendable () -> Void
        private var hasFired = false
        private let lock = NSLock()

        init(onFirstFrame: @escaping @Sendable () -> Void) {
            self.onFirstFrame = onFirstFrame
        }

        func setSize(_ size: CGSize) {}

        func renderFrame(_ frame: RTCVideoFrame?) {
            guard frame != nil else { return }
            let first = lock.withLock {
                defer { hasFired = true }
                return !hasFired
            }
            if first { onFirstFrame() }
        }
    }
}
