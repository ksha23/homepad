import Foundation
import HAKit
import HomePadCore

/// The Home Assistant WebSocket as WebRTC signaling sees it. HAKit in the app,
/// a fake in tests.
@MainActor
protocol HAWebRTCTransport: AnyObject {
    func send(_ request: HARequest) async throws -> JSONValue
    /// Starts a subscription. `onFailure` runs when Home Assistant refuses it.
    /// Cancelling the returned token unsubscribes, which closes the session there.
    func subscribe(_ request: HARequest, onEvent: @escaping @MainActor (JSONValue) -> Void,
                   onFailure: @escaping @MainActor (Error) -> Void) -> HACancellable
}

/// The other side of the negotiation: a peer connection that makes the offer and
/// takes the answer and the remote candidates.
@MainActor
protocol WebRTCPeer: AnyObject {
    /// Creates the offer and sets it as the local description.
    func makeOffer() async throws -> String
    func setAnswer(_ sdp: String) async throws
    func addRemoteCandidate(_ candidate: HAICECandidate) async
}

/// One `camera/webrtc/offer` exchange. Sends the offer, applies the answer, and
/// trickles candidates both ways: local ones wait for the session ID, remote ones
/// for the answer, since a candidate before its description is refused.
@MainActor
final class HAWebRTCNegotiation {
    enum Failure: Error, Equatable {
        /// Home Assistant refused the offer, for example a camera without WebRTC.
        case refused(code: String)
        /// The camera's provider reported an error during the session.
        case homeAssistant(code: String)
        case peer(String)
        case cancelled
    }

    let entityID: String
    private let transport: any HAWebRTCTransport
    private let peer: any WebRTCPeer
    private var subscription: HACancellable?
    private(set) var sessionID: String?
    private var localCandidates: [HAICECandidate] = []
    private var remoteCandidates: [HAICECandidate] = []
    private var hasAppliedAnswer = false
    private var answer: CheckedContinuation<String, Error>?
    private var isStopped = false

    /// An error Home Assistant sends once the stream runs, which ends it.
    var onSessionError: ((Failure) -> Void)?

    init(entityID: String, transport: any HAWebRTCTransport, peer: any WebRTCPeer) {
        self.entityID = entityID
        self.transport = transport
        self.peer = peer
    }

    /// Sends the offer and applies the answer. Returns the answer's SDP.
    func start() async throws -> String {
        let offer: String
        do {
            offer = try await peer.makeOffer()
        } catch {
            throw Failure.peer(error.localizedDescription)
        }
        guard !isStopped else { throw Failure.cancelled }
        let sdp = try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<String, Error>) in
                answer = continuation
                subscription = transport.subscribe(HARequests.webRTCOffer(entityID, sdp: offer)) { [weak self] json in
                    self?.handle(json)
                } onFailure: { [weak self] error in
                    let code = (error as? HAError).flatMap(Self.code(of:)) ?? "request_failed"
                    self?.resumeAnswer(throwing: Failure.refused(code: code))
                }
            }
        } onCancel: {
            Task { @MainActor [weak self] in self?.stop() }
        }
        do {
            try await peer.setAnswer(sdp)
        } catch {
            throw Failure.peer(error.localizedDescription)
        }
        hasAppliedAnswer = true
        let waiting = remoteCandidates
        remoteCandidates = []
        for candidate in waiting {
            await peer.addRemoteCandidate(candidate)
        }
        return sdp
    }

    /// A candidate the local peer gathered.
    func addLocalCandidate(_ candidate: HAICECandidate) {
        guard !isStopped else { return }
        if let sessionID {
            send(candidate, sessionID: sessionID)
        } else {
            localCandidates.append(candidate)
        }
    }

    /// Unsubscribes, which tells Home Assistant to close the session.
    func stop() {
        guard !isStopped else { return }
        isStopped = true
        subscription?.cancel()
        subscription = nil
        localCandidates = []
        remoteCandidates = []
        resumeAnswer(throwing: Failure.cancelled)
    }

    private func handle(_ json: JSONValue) {
        guard !isStopped, let event = HAWebRTCEvent(json: json) else { return }
        switch event {
        case .session(let id):
            sessionID = id
            let waiting = localCandidates
            localCandidates = []
            for candidate in waiting { send(candidate, sessionID: id) }
        case .answer(let sdp):
            guard let answer else { return }
            self.answer = nil
            answer.resume(returning: sdp)
        case .candidate(let candidate):
            if hasAppliedAnswer {
                Task { await peer.addRemoteCandidate(candidate) }
            } else {
                remoteCandidates.append(candidate)
            }
        case .error(let code, _):
            if answer != nil {
                resumeAnswer(throwing: Failure.homeAssistant(code: code))
            } else {
                onSessionError?(.homeAssistant(code: code))
            }
        }
    }

    private func send(_ candidate: HAICECandidate, sessionID: String) {
        let request = HARequests.webRTCCandidate(entityID, sessionID: sessionID, candidate: candidate)
        Task { _ = try? await transport.send(request) }
    }

    private func resumeAnswer(throwing error: Error) {
        guard let answer else { return }
        self.answer = nil
        answer.resume(throwing: error)
    }

    private static func code(of error: HAError) -> String? {
        if case .external(let external) = error { return external.code }
        return nil
    }
}

/// HAKit's connection as signaling. Holds it weakly, so a session that outlives a
/// new address or token does not keep the old connection open.
@MainActor
final class HAKitWebRTCTransport: HAWebRTCTransport {
    private weak var connection: HAConnection?

    init(connection: HAConnection) {
        self.connection = connection
    }

    func send(_ request: HARequest) async throws -> JSONValue {
        guard let connection else { throw SmartHomeError.notConnected(.homeAssistant) }
        return JSONValue(haData: try await connection.send(request))
    }

    func subscribe(_ request: HARequest, onEvent: @escaping @MainActor (JSONValue) -> Void,
                   onFailure: @escaping @MainActor (Error) -> Void) -> HACancellable {
        guard let connection else {
            onFailure(SmartHomeError.notConnected(.homeAssistant))
            return Cancelled()
        }
        // HAKit calls back on the main queue.
        return connection.subscribe(to: request, initiated: { result in
            guard case .failure(let error) = result else { return }
            MainActor.assumeIsolated { onFailure(error) }
        }, handler: { _, data in
            MainActor.assumeIsolated { onEvent(JSONValue(haData: data)) }
        })
    }

    private struct Cancelled: HACancellable {
        func cancel() {}
    }
}
