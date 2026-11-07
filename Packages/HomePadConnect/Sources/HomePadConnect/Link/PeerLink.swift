import Foundation
import HomePadCore
import Network
import Observation

/// The local-network link between HomePads and their companion iPhones and Macs.
///
/// - Discovery: Bonjour `_homepad._tcp` (NWListener advertises, NWBrowser finds).
/// - Security: devices share a household key, set up once with a 6-digit code.
///   Each connection runs an X25519 + HMAC handshake, then ChaChaPoly-sealed frames.
/// - Messages: `PeerMessage` (JSON body plus binary attachment).
///
/// Features register handlers per message type:
///
///     link.on(.intercomClip) { message, peer in ... }
///     try await link.send(message, to: peer.id)
@MainActor
@Observable
public final class PeerLink {
    public typealias Handler = @MainActor (PeerMessage, PeerDevice) -> Void

    /// Everything seen on the network or connected, excluding this device.
    public internal(set) var peers: [PeerDevice] = []
    public internal(set) var isRunning = false
    /// A problem worth showing, for example missing Local Network permission.
    public internal(set) var problem: String?
    public internal(set) var household: HouseholdCredentials?
    public internal(set) var pairingWindow: PairingWindow?
    public internal(set) var identity: LocalIdentity

    @ObservationIgnored let services: AppServices
    @ObservationIgnored var listener: NWListener?
    @ObservationIgnored var browser: NWBrowser?
    @ObservationIgnored var endpoints: [String: NWEndpoint] = [:]
    @ObservationIgnored var sessions: [String: PeerConnection] = [:]
    @ObservationIgnored var handshaking: [ObjectIdentifier: PeerConnection] = [:]
    @ObservationIgnored var dialWaiters: [String: [CheckedContinuation<PeerConnection, Error>]] = [:]
    @ObservationIgnored var joinContinuation: CheckedContinuation<HouseholdCredentials, Error>?
    @ObservationIgnored var joinConnectionID: ObjectIdentifier?
    @ObservationIgnored private var handlers: [PeerMessageType: [Handler]] = [:]
    @ObservationIgnored private var connectHandlers: [@MainActor (PeerDevice) -> Void] = []
    @ObservationIgnored private var disconnectHandlers: [@MainActor (String) -> Void] = []
    @ObservationIgnored let log = Log.make("PeerLink")

    public init(services: AppServices) {
        self.services = services
        self.identity = LocalDevice.identity(settings: services.settings)
        self.household = HouseholdCredentials.load(from: services.keychain)
    }

    // MARK: Queries

    /// Peers in our household.
    public var members: [PeerDevice] { peers.filter { $0.isMember(of: household) } }
    /// HomePads in our household, the usual targets for intercom and sharing.
    public var homePads: [PeerDevice] { members.filter { $0.kind == .homePad } }
    /// Paired iPhones and Macs.
    public var companions: [PeerDevice] { members.filter { $0.kind.isCompanion } }
    /// HomePads nearby that show a pairing code right now.
    public var pairableHomePads: [PeerDevice] {
        peers.filter { $0.isAcceptingPairing && !$0.isMember(of: household) }
    }

    public func peer(_ id: String) -> PeerDevice? { peers.first { $0.id == id } }

    // MARK: Handlers

    /// Calls `handler` for every authenticated message of `type`.
    public func on(_ type: PeerMessageType, handler: @escaping Handler) {
        handlers[type, default: []].append(handler)
    }

    /// Calls `handler` whenever a session with a household member opens.
    public func onConnect(_ handler: @escaping @MainActor (PeerDevice) -> Void) {
        connectHandlers.append(handler)
    }

    /// Hands an authenticated message to the handlers for its type. Sessions
    /// call it for every message, and tests call it to play the other device.
    func dispatch(_ message: PeerMessage, from device: PeerDevice) {
        handlers[message.type]?.forEach { $0(message, device) }
    }

    /// Calls `handler` with the device ID whenever an open session with it closes.
    public func onDisconnect(_ handler: @escaping @MainActor (String) -> Void) {
        disconnectHandlers.append(handler)
    }

    // MARK: Sending

    /// A message from this device with a typed body.
    public func message<Content: Encodable>(_ type: PeerMessageType, _ content: Content, attachment: Data? = nil) throws -> PeerMessage {
        try PeerMessage(type: type, sender: identity.deviceID, content: content, attachment: attachment)
    }

    /// Sends to one household member, connecting first if needed.
    public func send(_ message: PeerMessage, to peerID: String) async throws {
        let connection = try await session(with: peerID)
        try connection.send(message)
    }

    /// Sends to one household member only on the session `sessionID` names,
    /// the one a request came in on. Throws when that session has closed or a
    /// newer one replaced it, so an answer never goes to a different session.
    public func send(_ message: PeerMessage, to peerID: String, onSession sessionID: UUID) throws {
        guard let open = sessions[peerID], open.isEstablished, open.sessionID == sessionID else {
            throw PeerLinkError.notConnected
        }
        try open.send(message)
    }

    /// The session open with a member right now, if any.
    public func sessionID(with peerID: String) -> UUID? {
        guard let open = sessions[peerID], open.isEstablished else { return nil }
        return open.sessionID
    }

    /// Sends to every reachable member that matches `filter`, in parallel. Returns the IDs that got it.
    @discardableResult
    public func broadcast(_ message: PeerMessage, where filter: (PeerDevice) -> Bool = { _ in true }) async -> [String] {
        let targets = members.filter(filter)
        return await withTaskGroup(of: String?.self) { group in
            for peer in targets {
                group.addTask { @MainActor in
                    do {
                        try await self.send(message, to: peer.id)
                        return peer.id
                    } catch {
                        self.log.info("Broadcast to \(peer.name, privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
                        return nil
                    }
                }
            }
            var delivered: [String] = []
            for await id in group {
                if let id { delivered.append(id) }
            }
            return delivered
        }
    }

    /// Sends to one household member, or to every reachable HomePad when
    /// `peerID` is nil: the choice behind sharing, intercom and the companion
    /// remote. Returns the IDs that got it. One peer throws when it fails, a
    /// broadcast logs failures and returns fewer IDs.
    @discardableResult
    public func send(_ message: PeerMessage, toHomePad peerID: String?) async throws -> [String] {
        guard let peerID else { return await broadcast(message) { $0.kind == .homePad } }
        try await send(message, to: peerID)
        return [peerID]
    }

    // MARK: Sessions

    /// An authenticated connection to a member, reusing an open one.
    func session(with peerID: String) async throws -> PeerConnection {
        if let open = sessions[peerID], open.isEstablished { return open }
        guard household != nil else { throw PeerLinkError.notPaired }
        guard let endpoint = endpoints[peerID] else {
            throw PeerLinkError.peerUnavailable(peer(peerID)?.name ?? "That device")
        }
        if dialWaiters[peerID] == nil {
            dialWaiters[peerID] = []
            dial(peerID, at: endpoint)
        }
        return try await withCheckedThrowingContinuation { continuation in
            dialWaiters[peerID, default: []].append(continuation)
        }
    }

    private func dial(_ peerID: String, at endpoint: NWEndpoint) {
        let engine = HandshakeEngine(role: .initiator, local: identity, intent: .session, credentials: household)
        let connection = PeerConnection(connection: NWConnection(to: endpoint, using: Self.parameters()), engine: engine)
        track(connection)
        connection.start()
        Task { @MainActor [weak self, weak connection] in
            try? await Task.sleep(for: .seconds(8))
            guard let self, self.dialWaiters[peerID] != nil else { return }
            self.finishDial(peerID, with: .failure(PeerLinkError.timedOut))
            connection?.cancel(error: PeerLinkError.timedOut)
        }
    }

    func finishDial(_ peerID: String, with result: Result<PeerConnection, Error>) {
        let waiters = dialWaiters.removeValue(forKey: peerID) ?? []
        waiters.forEach { $0.resume(with: result) }
    }

    /// Wires a connection's events into the link.
    func track(_ connection: PeerConnection) {
        handshaking[ObjectIdentifier(connection)] = connection
        connection.onEvent = { [weak self] connection, event in
            self?.handle(event, from: connection)
        }
    }

    private func handle(_ event: PeerConnection.Event, from connection: PeerConnection) {
        switch event {
        case .established(let hello):
            handshaking[ObjectIdentifier(connection)] = nil
            let old = sessions[hello.deviceID]
            if let old, old !== connection, old.isEstablished, !Self.keepsNewSession(
                newIsInitiator: connection.isInitiator, oldIsInitiator: old.isInitiator,
                local: identity.deviceID, remote: hello.deviceID
            ) {
                // Both devices dialed at once. Each keeps the one the lower ID dialed, so they talk on the same one.
                log.info("Session with \(hello.name, privacy: .public) opened twice, keeping the one the lower ID dialed")
                finishDial(hello.deviceID, with: .success(old))
                connection.cancel()
                return
            }
            if let old, old !== connection { old.cancel() }
            sessions[hello.deviceID] = connection
            let device = upsertPeer(from: hello, connected: true)
            finishDial(hello.deviceID, with: .success(connection))
            connectHandlers.forEach { $0(device) }
        case .message(let message):
            guard let hello = connection.peer, var device = peer(hello.deviceID) else { return }
            device.sessionID = connection.sessionID
            dispatch(message, from: device)
        case .joined(let credentials, let host):
            completeJoin(credentials, host: host)
        case .admitted(let hello):
            admitted(hello)
        case .closed(let error):
            handshaking[ObjectIdentifier(connection)] = nil
            if let id = connection.peer?.deviceID {
                if sessions[id] === connection {
                    sessions[id] = nil
                    setConnected(false, peerID: id)
                    disconnectHandlers.forEach { $0(id) }
                }
                finishDial(id, with: .failure(error ?? PeerLinkError.notConnected))
            }
            connectionClosed(connection, error: error)
        }
    }

    /// Whether a new session replaces an open one with the same device.
    ///
    /// When both devices dial each other at once, as when a HomePad sends to a
    /// phone that is connecting to it, each side sees two sessions, in either
    /// order. Both keep the one the device with the lower ID dialed, so they
    /// never each keep a different one and send into a connection the other
    /// side closed. Two sessions dialed by the same device are a reconnect, and
    /// the newer one wins.
    nonisolated static func keepsNewSession(newIsInitiator: Bool, oldIsInitiator: Bool, local: String, remote: String) -> Bool {
        guard newIsInitiator != oldIsInitiator else { return true }
        let lowerDialedNew = newIsInitiator ? local < remote : remote < local
        return lowerDialedNew
    }

    @discardableResult
    func upsertPeer(from hello: HelloBody, connected: Bool) -> PeerDevice {
        if let index = peers.firstIndex(where: { $0.id == hello.deviceID }) {
            peers[index].name = hello.name
            peers[index].householdID = hello.householdID
            peers[index].isConnected = connected
            peers[index].lastSeen = Date()
            return peers[index]
        }
        let device = PeerDevice(id: hello.deviceID, name: hello.name, kind: hello.kind,
                                householdID: hello.householdID, isConnected: connected)
        peers.append(device)
        return device
    }

    private func setConnected(_ connected: Bool, peerID: String) {
        guard let index = peers.firstIndex(where: { $0.id == peerID }) else { return }
        peers[index].isConnected = connected
    }

    func dropAllSessions() {
        sessions.values.forEach { $0.cancel() }
        handshaking.values.forEach { $0.cancel() }
        sessions = [:]
        handshaking = [:]
    }

    /// TCP with keepalive, peer-to-peer Wi-Fi allowed.
    static func parameters() -> NWParameters {
        let tcp = NWProtocolTCP.Options()
        tcp.enableKeepalive = true
        tcp.keepaliveIdle = 30
        let parameters = NWParameters(tls: nil, tcp: tcp)
        parameters.includePeerToPeer = true
        return parameters
    }
}
