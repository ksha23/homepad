import Foundation
import WebRTC

/// What the peer connection reports, in order, from WebRTC's threads.
enum WebRTCPeerEvent: Sendable {
    case localCandidate(HAICECandidate)
    case state(WebRTCConnectionState)
}

/// ICE and DTLS together (`RTCPeerConnectionState`).
enum WebRTCConnectionState: Sendable {
    case new, connecting, connected, disconnected, failed, closed
}

/// One receive-only peer connection to a Home Assistant camera: video, the
/// camera's sound when asked, and a send slot for talk when the camera has a
/// speaker. Closing it ends the media at once. Home Assistant's session ends
/// separately, with the offer's subscription.
@MainActor
final class WebRTCPeerConnection: WebRTCPeer {
    struct Media: Equatable {
        var receivesAudio: Bool
        /// Offer audio both ways. Nothing is sent until a talk track goes on the sender.
        var offersTalk: Bool
    }

    let events: AsyncStream<WebRTCPeerEvent>
    private let connection: RTCPeerConnection
    private let observer: Observer
    private let factory: RTCPeerConnectionFactory
    private var videoTransceiver: RTCRtpTransceiver?
    private var audioTransceiver: RTCRtpTransceiver?
    private var talkTrack: RTCAudioTrack?
    private var dataChannel: RTCDataChannel?
    private static let constraints = RTCMediaConstraints(mandatoryConstraints: nil, optionalConstraints: nil)

    init?(factory: RTCPeerConnectionFactory, config: HAWebRTCClientConfig, media: Media) {
        let configuration = RTCConfiguration()
        configuration.iceServers = config.iceServers.map {
            RTCIceServer(urlStrings: $0.urls, username: $0.username, credential: $0.credential)
        }
        configuration.sdpSemantics = .unifiedPlan
        configuration.bundlePolicy = .maxBundle
        configuration.rtcpMuxPolicy = .require
        // New interfaces (Wi-Fi coming back) keep gathering, so a short drop can recover.
        configuration.continualGatheringPolicy = .gatherContinually
        let (events, continuation) = AsyncStream.makeStream(of: WebRTCPeerEvent.self)
        let observer = Observer(continuation: continuation)
        guard let connection = factory.peerConnection(with: configuration, constraints: Self.constraints, delegate: observer) else {
            continuation.finish()
            return nil
        }
        self.factory = factory
        self.connection = connection
        self.observer = observer
        self.events = events

        let audioInit = RTCRtpTransceiverInit()
        audioInit.direction = media.offersTalk ? .sendRecv : .recvOnly
        if media.receivesAudio || media.offersTalk {
            audioTransceiver = connection.addTransceiver(of: .audio, init: audioInit)
        }
        let videoInit = RTCRtpTransceiverInit()
        videoInit.direction = .recvOnly
        videoTransceiver = connection.addTransceiver(of: .video, init: videoInit)
        // Some cameras (Nest) stream only while a data channel is open.
        if let label = config.dataChannel {
            dataChannel = connection.dataChannel(forLabel: label, configuration: RTCDataChannelConfiguration())
        }
    }

    var videoTrack: RTCVideoTrack? { videoTransceiver?.receiver.track as? RTCVideoTrack }
    var audioTrack: RTCAudioTrack? { audioTransceiver?.receiver.track as? RTCAudioTrack }

    func makeOffer() async throws -> String {
        let connection = self.connection
        let offer: RTCSessionDescription = try await withCheckedThrowingContinuation { continuation in
            connection.offer(for: Self.constraints) { description, error in
                if let description {
                    continuation.resume(returning: description)
                } else {
                    continuation.resume(throwing: error ?? PeerError.noDescription)
                }
            }
        }
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            connection.setLocalDescription(offer) { error in
                if let error { continuation.resume(throwing: error) } else { continuation.resume() }
            }
        }
        return offer.sdp
    }

    func setAnswer(_ sdp: String) async throws {
        let connection = self.connection
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            connection.setRemoteDescription(RTCSessionDescription(type: .answer, sdp: sdp)) { error in
                if let error { continuation.resume(throwing: error) } else { continuation.resume() }
            }
        }
    }

    func addRemoteCandidate(_ candidate: HAICECandidate) async {
        let ice = RTCIceCandidate(sdp: candidate.candidate, sdpMLineIndex: candidate.sdpMLineIndex ?? 0, sdpMid: candidate.sdpMid)
        let connection = self.connection
        // A candidate the camera cannot use is skipped. Others may still connect.
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            connection.add(ice) { _ in continuation.resume() }
        }
    }

    /// Puts the microphone on the talk sender, or takes it off. WebRTC then
    /// starts or stops recording through `WebRTCAudioDevice`.
    func setSending(_ sending: Bool) {
        guard let sender = audioTransceiver?.sender else { return }
        if sending {
            let track = talkTrack ?? factory.audioTrack(with: factory.audioSource(with: Self.constraints), trackId: "homepad-talk")
            talkTrack = track
            sender.track = track
        } else {
            sender.track = nil
        }
    }

    func close() {
        audioTransceiver?.sender.track = nil
        dataChannel?.close()
        connection.close()
        observer.finish()
    }

    private enum PeerError: LocalizedError {
        case noDescription
        var errorDescription: String? { "WebRTC made no offer." }
    }

    /// WebRTC holds its delegate weakly and calls it on its signaling thread.
    /// The stream takes events from any thread.
    private final class Observer: NSObject, RTCPeerConnectionDelegate, @unchecked Sendable {
        private let continuation: AsyncStream<WebRTCPeerEvent>.Continuation

        init(continuation: AsyncStream<WebRTCPeerEvent>.Continuation) {
            self.continuation = continuation
        }

        func finish() { continuation.finish() }

        func peerConnection(_ peerConnection: RTCPeerConnection, didGenerate candidate: RTCIceCandidate) {
            continuation.yield(.localCandidate(HAICECandidate(
                candidate: candidate.sdp, sdpMid: candidate.sdpMid, sdpMLineIndex: candidate.sdpMLineIndex)))
        }

        func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCPeerConnectionState) {
            let state: WebRTCConnectionState = switch newState {
            case .new: .new
            case .connecting: .connecting
            case .connected: .connected
            case .disconnected: .disconnected
            case .failed: .failed
            case .closed: .closed
            @unknown default: .failed
            }
            continuation.yield(.state(state))
        }

        func peerConnection(_ peerConnection: RTCPeerConnection, didChange stateChanged: RTCSignalingState) {}
        func peerConnection(_ peerConnection: RTCPeerConnection, didAdd stream: RTCMediaStream) {}
        func peerConnection(_ peerConnection: RTCPeerConnection, didRemove stream: RTCMediaStream) {}
        func peerConnectionShouldNegotiate(_ peerConnection: RTCPeerConnection) {}
        func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCIceConnectionState) {}
        func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCIceGatheringState) {}
        func peerConnection(_ peerConnection: RTCPeerConnection, didRemove candidates: [RTCIceCandidate]) {}
        func peerConnection(_ peerConnection: RTCPeerConnection, didOpen dataChannel: RTCDataChannel) {}
    }
}
