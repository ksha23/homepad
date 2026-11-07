import Foundation
import HAKit
import HomePadCore
import Testing
@testable import HomePadSmartHome

/// Home Assistant's WebRTC signaling (`camera/webrtc/*`) against hand-written
/// messages in the shape Home Assistant 2026.11 sends them, through a fake
/// transport and a fake peer. Nothing touches a network or WebRTC itself.
@MainActor
@Suite("Home Assistant WebRTC signaling")
struct HAWebRTCSignalingTests {
    // MARK: Messages

    @Test func capabilitiesWithTwoWayAudio() {
        let capabilities = HACameraCapabilities(json: JSONValue(haData: Fixtures.resultData("ws_result_camera_capabilities")))
        #expect(capabilities.supportsWebRTC)
        #expect(capabilities.supportsHLS)
        #expect(capabilities.twoWayAudio)
    }

    @Test func capabilitiesBeforeTwoWayAudioExisted() {
        let capabilities = HACameraCapabilities(json: JSONValue(haData: Fixtures.resultData("ws_result_camera_capabilities_hls")))
        #expect(!capabilities.supportsWebRTC)
        #expect(capabilities.supportsHLS)
        #expect(!capabilities.twoWayAudio, "servers before 2026.11 leave the key out")
    }

    @Test func clientConfigReadsEveryICEServerShape() {
        let config = HAWebRTCClientConfig(json: JSONValue(haData: Fixtures.resultData("ws_result_webrtc_client_config")))
        #expect(config.iceServers == [
            .init(urls: ["stun:stun.home-assistant.io:80"]),
            .init(urls: ["turn:turn.example.test:3478?transport=udp", "turns:turn.example.test:5349"],
                  username: "homepad", credential: "not-a-real-secret"),
        ], "one URL as a string, several as a list, and a server without URLs left out")
        #expect(config.dataChannel == "dataSendChannel")
    }

    @Test func eventsDecode() {
        #expect(HAWebRTCEvent(json: event("ws_event_webrtc_session")) == .session(id: "01JC8Z3V2X4N5Q6R7S8T9V0W1X"))
        guard case .answer(let sdp) = HAWebRTCEvent(json: event("ws_event_webrtc_answer")) else {
            Issue.record("expected an answer")
            return
        }
        #expect(sdp.hasPrefix("v=0\r\n"))
        #expect(HAWebRTCEvent(json: event("ws_event_webrtc_error"))
            == .error(code: "go2rtc_webrtc_offer_failed", message: "streams: dial tcp 192.168.1.30:554: i/o timeout"))
        #expect(HAWebRTCEvent(json: ["type": "something_new"]) == nil, "unknown events are skipped")
    }

    @Test func go2rtcCandidateGetsLineZero() throws {
        guard case .candidate(let candidate) = HAWebRTCEvent(json: event("ws_event_webrtc_candidate")) else {
            Issue.record("expected a candidate")
            return
        }
        #expect(candidate.candidate == "candidate:3197346385 1 udp 2130706431 192.168.1.20 8555 typ host")
        #expect(candidate.sdpMid == nil)
        #expect(candidate.sdpMLineIndex == 0)
        let bare = try #require(HAICECandidate(json: ["candidate": "candidate:1 1 udp 1 10.0.0.2 9 typ host"]))
        #expect(bare.sdpMLineIndex == 0, "neither mid nor index means the first line, as Home Assistant reads it")
        #expect(HAICECandidate(json: ["candidate": ""]) == nil, "an end of candidates is not a candidate")
    }

    @Test func candidateRequestShape() {
        let candidate = HAICECandidate(candidate: "candidate:9 1 udp 5 10.0.0.9 5000 typ host", sdpMid: "1", sdpMLineIndex: 1)
        let request = HARequests.webRTCCandidate("camera.front_door", sessionID: "S1", candidate: candidate)
        #expect(request.type == "camera/webrtc/candidate")
        #expect(request.data["entity_id"] as? String == "camera.front_door")
        #expect(request.data["session_id"] as? String == "S1")
        let body = request.data["candidate"] as? [String: Any]
        #expect(body?["candidate"] as? String == candidate.candidate)
        #expect(body?["sdpMid"] as? String == "1")
        #expect(body?["sdpMLineIndex"] as? Int == 1)
        #expect(!request.shouldRetry)
    }

    // MARK: Negotiation

    @Test func offerAnswerAndCandidatesBothWays() async throws {
        let transport = FakeWebRTCTransport()
        let peer = FakePeer()
        let negotiation = HAWebRTCNegotiation(entityID: "camera.front_door", transport: transport, peer: peer)
        let started = Task { try await negotiation.start() }
        #expect(await eventually { transport.subscriptions.count == 1 })
        let offer = try #require(transport.subscriptions.first)
        #expect(offer.request.type == "camera/webrtc/offer")
        #expect(offer.request.data["entity_id"] as? String == "camera.front_door")
        #expect(offer.request.data["offer"] as? String == peer.offer)
        #expect(!offer.request.shouldRetry, "an offer answered on a new connection belongs to a closed peer")

        // Gathered before Home Assistant names the session: held back.
        let early = HAICECandidate(candidate: "candidate:1 1 udp 1 10.0.0.2 50000 typ host", sdpMid: "0", sdpMLineIndex: 0)
        negotiation.addLocalCandidate(early)
        #expect(transport.sent.isEmpty)

        // A remote candidate before the answer: held until the answer is set.
        transport.push(event("ws_event_webrtc_candidate"))
        transport.push(event("ws_event_webrtc_session"))
        #expect(await eventually { transport.sent.count == 1 })
        #expect(transport.sent.first?.data["session_id"] as? String == "01JC8Z3V2X4N5Q6R7S8T9V0W1X")
        #expect(peer.remoteCandidates.isEmpty)

        transport.push(event("ws_event_webrtc_answer"))
        let answer = try await started.value
        #expect(peer.answers == [answer])
        #expect(peer.remoteCandidates.map(\.candidate) == ["candidate:3197346385 1 udp 2130706431 192.168.1.20 8555 typ host"])

        // After the session is known, local candidates go straight out.
        negotiation.addLocalCandidate(HAICECandidate(candidate: "candidate:2 1 udp 1 10.0.0.2 50001 typ host", sdpMid: "0", sdpMLineIndex: 0))
        #expect(await eventually { transport.sent.count == 2 })

        // And remote ones are applied as they come.
        transport.push(event("ws_event_webrtc_candidate"))
        #expect(await eventually { peer.remoteCandidates.count == 2 })

        negotiation.stop()
        #expect(offer.isCancelled, "unsubscribing closes the session in Home Assistant")
    }

    @Test func refusedOfferThrowsItsCode() async {
        let transport = FakeWebRTCTransport()
        let negotiation = HAWebRTCNegotiation(entityID: "camera.backyard", transport: transport, peer: FakePeer())
        let started = Task { try await negotiation.start() }
        #expect(await eventually { transport.subscriptions.count == 1 })
        transport.refuse(Fixtures.object("ws_result_webrtc_offer_error"))
        await #expect(throws: HAWebRTCNegotiation.Failure.refused(code: "webrtc_offer_failed")) { try await started.value }
    }

    @Test func providerErrorBeforeTheAnswerThrows() async {
        let transport = FakeWebRTCTransport()
        let negotiation = HAWebRTCNegotiation(entityID: "camera.backyard", transport: transport, peer: FakePeer())
        let started = Task { try await negotiation.start() }
        #expect(await eventually { transport.subscriptions.count == 1 })
        transport.push(event("ws_event_webrtc_session"))
        transport.push(event("ws_event_webrtc_error"))
        await #expect(throws: HAWebRTCNegotiation.Failure.homeAssistant(code: "go2rtc_webrtc_offer_failed")) { try await started.value }
    }

    @Test func providerErrorAfterTheAnswerEndsTheSession() async throws {
        let transport = FakeWebRTCTransport()
        let negotiation = HAWebRTCNegotiation(entityID: "camera.backyard", transport: transport, peer: FakePeer())
        var ended: HAWebRTCNegotiation.Failure?
        negotiation.onSessionError = { ended = $0 }
        let started = Task { try await negotiation.start() }
        #expect(await eventually { transport.subscriptions.count == 1 })
        transport.push(event("ws_event_webrtc_session"))
        transport.push(event("ws_event_webrtc_answer"))
        _ = try await started.value
        transport.push(event("ws_event_webrtc_error"))
        #expect(ended == .homeAssistant(code: "go2rtc_webrtc_offer_failed"))
    }

    @Test func stoppingWhileWaitingEndsTheWaitAndUnsubscribes() async {
        let transport = FakeWebRTCTransport()
        let peer = FakePeer()
        let negotiation = HAWebRTCNegotiation(entityID: "camera.backyard", transport: transport, peer: peer)
        let started = Task { try await negotiation.start() }
        #expect(await eventually { transport.subscriptions.count == 1 })
        negotiation.stop()
        await #expect(throws: HAWebRTCNegotiation.Failure.cancelled) { try await started.value }
        #expect(transport.subscriptions.first?.isCancelled == true)
        // Late events of a stopped session change nothing.
        transport.push(event("ws_event_webrtc_answer"))
        negotiation.addLocalCandidate(HAICECandidate(candidate: "candidate:3 1 udp 1 10.0.0.2 50002 typ host", sdpMid: "0", sdpMLineIndex: 0))
        #expect(peer.answers.isEmpty)
        #expect(transport.sent.isEmpty)
    }

    // MARK: Session descriptions

    @Test func answerSaysWhatFlows() throws {
        guard case .answer(let sdp) = HAWebRTCEvent(json: event("ws_event_webrtc_answer")) else {
            Issue.record("expected an answer")
            return
        }
        let media = SDPMedia(sdp: sdp)
        #expect(media.hasAudio)
        #expect(media.hasVideo)
        #expect(media.acceptsAudio, "a sendrecv audio line takes our sound: talk works")
    }

    @Test func directionsAndRefusedLines() {
        let listenOnly = SDPMedia(sdp: "v=0\r\nm=audio 9 UDP/TLS/RTP/SAVPF 111\r\na=sendonly\r\nm=video 9 UDP/TLS/RTP/SAVPF 96\r\na=sendonly\r\n")
        #expect(listenOnly.hasAudio)
        #expect(!listenOnly.acceptsAudio, "a camera without a speaker only sends")
        let refused = SDPMedia(sdp: "v=0\r\nm=audio 0 UDP/TLS/RTP/SAVPF 0\r\na=inactive\r\nm=video 9 UDP/TLS/RTP/SAVPF 96\r\n")
        #expect(refused.direction(of: "audio") == nil, "port 0 refuses the line")
        #expect(!refused.hasAudio)
        #expect(refused.direction(of: "video") == .sendrecv, "no attribute means sendrecv")
        let silent = SDPMedia(sdp: "v=0\nm=video 9 UDP/TLS/RTP/SAVPF 96\na=sendonly\n")
        #expect(!silent.hasAudio && silent.hasVideo, "plain newlines read the same")
    }

    // MARK: Helpers

    private func event(_ name: String) -> JSONValue {
        JSONValue(haData: Fixtures.eventData(name))
    }
}

/// Records what signaling sends and lets a test play Home Assistant's side.
@MainActor
final class FakeWebRTCTransport: HAWebRTCTransport {
    final class Subscription: HACancellable {
        let request: HARequest
        let onEvent: @MainActor (JSONValue) -> Void
        let onFailure: @MainActor (Error) -> Void
        private(set) var isCancelled = false

        init(request: HARequest, onEvent: @escaping @MainActor (JSONValue) -> Void, onFailure: @escaping @MainActor (Error) -> Void) {
            self.request = request
            self.onEvent = onEvent
            self.onFailure = onFailure
        }

        func cancel() { isCancelled = true }
    }

    private(set) var sent: [HARequest] = []
    private(set) var subscriptions: [Subscription] = []

    func send(_ request: HARequest) async throws -> JSONValue {
        sent.append(request)
        return .object([:])
    }

    func subscribe(_ request: HARequest, onEvent: @escaping @MainActor (JSONValue) -> Void,
                   onFailure: @escaping @MainActor (Error) -> Void) -> HACancellable {
        let subscription = Subscription(request: request, onEvent: onEvent, onFailure: onFailure)
        subscriptions.append(subscription)
        return subscription
    }

    /// An event on the newest subscription that is still open.
    func push(_ event: JSONValue) {
        guard let subscription = subscriptions.last, !subscription.isCancelled else { return }
        subscription.onEvent(event)
    }

    /// Home Assistant's `send_error` for the subscription, as HAKit reports it.
    func refuse(_ message: Any) {
        let error = (message as? [String: Any])?["error"] as? [String: String] ?? [:]
        subscriptions.last?.onFailure(HAError.external(.init(code: error["code"] ?? "", message: error["message"] ?? "")))
    }
}

@MainActor
final class FakePeer: WebRTCPeer {
    let offer = "v=0\r\no=- 1 1 IN IP4 127.0.0.1\r\ns=-\r\nt=0 0\r\nm=video 9 UDP/TLS/RTP/SAVPF 96\r\na=recvonly\r\n"
    private(set) var answers: [String] = []
    private(set) var remoteCandidates: [HAICECandidate] = []

    func makeOffer() async throws -> String { offer }
    func setAnswer(_ sdp: String) async throws { answers.append(sdp) }
    func addRemoteCandidate(_ candidate: HAICECandidate) async { remoteCandidates.append(candidate) }
}
