import Foundation
import HomePadCore
import Network

/// One TCP connection to another device: runs the handshake, then carries
/// sealed messages. All callbacks arrive on the main queue.
@MainActor
final class PeerConnection {
    enum Event {
        case established(HelloBody)
        case joined(HouseholdCredentials, host: HelloBody)
        case admitted(HelloBody)
        case message(PeerMessage)
        case closed(Error?)
    }

    let connection: NWConnection
    /// Names this connection, so handlers can tell one session with a device from the next.
    let sessionID = UUID()
    private var engine: HandshakeEngine
    private var channel: SecureChannel?
    private var decoder = FrameDecoder()
    private var isClosed = false
    private(set) var peer: HelloBody?
    var onEvent: (PeerConnection, Event) -> Void = { _, _ in }

    private let log = Log.make("PeerLink")

    init(connection: NWConnection, engine: HandshakeEngine) {
        self.connection = connection
        self.engine = engine
    }

    var isEstablished: Bool { channel != nil }
    /// True when this device dialed the connection.
    var isInitiator: Bool { engine.role == .initiator }

    func start() {
        connection.stateUpdateHandler = { [weak self] state in
            MainActor.assumeIsolated { self?.handle(state) }
        }
        connection.start(queue: .main)
        receive()
    }

    /// Seals and sends an app message. Only valid once established.
    func send(_ message: PeerMessage) throws {
        guard var channel else { throw PeerLinkError.notConnected }
        let sealed = try channel.seal(MessageCodec.encode(message))
        self.channel = channel
        write(sealed)
    }

    func cancel(error: Error? = nil) {
        guard !isClosed else { return }
        isClosed = true
        connection.cancel()
        onEvent(self, .closed(error))
    }

    // MARK: Private

    private func handle(_ state: NWConnection.State) {
        switch state {
        case .ready:
            do {
                try perform(engine.start())
            } catch {
                fail(error)
            }
        case .failed(let error):
            cancel(error: error)
        case .cancelled:
            cancel()
        default:
            break
        }
    }

    private func receive() {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 256 * 1024) { [weak self] data, _, isComplete, error in
            MainActor.assumeIsolated {
                guard let self, !self.isClosed else { return }
                if let data, !data.isEmpty { self.consume(data) }
                if let error {
                    self.cancel(error: error)
                } else if isComplete {
                    self.cancel()
                } else {
                    self.receive()
                }
            }
        }
    }

    private func consume(_ data: Data) {
        do {
            for frame in try decoder.append(data) where !isClosed {
                try handleFrame(frame)
            }
        } catch {
            fail(error)
        }
    }

    private func handleFrame(_ frame: Data) throws {
        if var channel {
            let message = try MessageCodec.decode(channel.open(frame))
            self.channel = channel
            onEvent(self, .message(message))
            return
        }
        let message = try MessageCodec.decode(frame)
        guard message.type.isHandshake else { throw HandshakeError.unexpected(message.type) }
        try perform(engine.receive(message))
    }

    private func perform(_ steps: [HandshakeEngine.Step]) throws {
        for step in steps {
            switch step {
            case .send(let message):
                write(try MessageCodec.encode(message))
            case .established(let channel, let peer):
                self.channel = channel
                self.peer = peer
                onEvent(self, .established(peer))
            case .joined(let household, let host):
                peer = host
                onEvent(self, .joined(household, host: host))
                close(after: 0.2)
            case .admitted(let peer):
                self.peer = peer
                onEvent(self, .admitted(peer))
                close(after: 1)
            }
        }
    }

    /// Tells the other side why (when useful), then closes.
    private func fail(_ error: Error) {
        log.error("Peer connection failed: \(String(describing: error), privacy: .public)")
        if let reason = (error as? HandshakeError)?.rejectReason,
           let reject = try? PeerMessage(type: .reject, sender: "", content: RejectBody(reason: reason)),
           let data = try? MessageCodec.encode(reject) {
            write(data)
            close(after: 0.3, error: error)
        } else {
            cancel(error: error)
        }
    }

    private func close(after delay: TimeInterval, error: Error? = nil) {
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            self?.cancel(error: error)
        }
    }

    private func write(_ body: Data) {
        connection.send(content: FrameDecoder.frame(body), completion: .contentProcessed { [weak self] error in
            guard let error else { return }
            MainActor.assumeIsolated { self?.cancel(error: error) }
        })
    }
}

/// Errors surfaced by the peer link to callers.
public enum PeerLinkError: LocalizedError, Equatable {
    case notConnected
    case notPaired
    case peerUnavailable(String)
    case timedOut
    case pairingFailed(String)

    public var errorDescription: String? {
        switch self {
        case .notConnected: "Not connected to that device."
        case .notPaired: "Pair this device with your HomePad first."
        case .peerUnavailable(let name): "\(name) is not reachable right now."
        case .timedOut: "The other device did not answer."
        case .pairingFailed(let reason): reason
        }
    }
}
