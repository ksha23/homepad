import CryptoKit
import Foundation

/// Who this device is on the link.
public struct LocalIdentity: Equatable, Sendable {
    public var deviceID: String
    public var name: String
    public var kind: DeviceKind

    public init(deviceID: String, name: String, kind: DeviceKind) {
        self.deviceID = deviceID
        self.name = name
        self.kind = kind
    }
}

/// Why a handshake stopped.
public enum HandshakeError: Error, Equatable {
    case unexpected(PeerMessageType)
    case rejected(RejectBody.Reason)
    case unsupportedVersion
    case wrongHousehold
    case badProof
    case pairingClosed
    case wrongCode
    case noHousehold

    /// What to tell the other side before closing, if anything.
    var rejectReason: RejectBody.Reason? {
        switch self {
        case .unsupportedVersion: .unsupportedVersion
        case .wrongHousehold, .noHousehold: .wrongHousehold
        case .badProof: .badProof
        case .pairingClosed: .pairingClosed
        case .wrongCode: .wrongCode
        case .unexpected, .rejected: nil
        }
    }
}

/// The handshake as a pure state machine, with no sockets, so it is unit tested
/// end to end. A connection feeds it messages and acts on the steps it returns.
///
/// Session (both sides already in the household):
///
///     I -> R  hello            R -> I  hello
///     I -> R  auth(proof I)    R -> I  auth(proof R)      then everything is sealed
///
/// Pairing (initiator types the host's 6-digit code):
///
///     I -> R  hello(pair)      R -> I  hello
///     I -> R  pair.proof       R -> I  pair.grant(sealed household key, proof R)
public struct HandshakeEngine {
    public static let protocolVersion = 1

    public enum Step {
        case send(PeerMessage)
        /// The session is authenticated. Use the channel for all further frames.
        case established(SecureChannel, peer: HelloBody)
        /// Initiator: the host accepted the code and shared its household.
        case joined(HouseholdCredentials, host: HelloBody)
        /// Responder: a new device proved the code and received the household key.
        case admitted(peer: HelloBody)
    }

    private enum State { case idle, awaitingHello, awaitingAuth, awaitingPairProof, awaitingGrant, done }

    public let role: KeySchedule.Role
    public let intent: HandshakeIntent
    private let local: LocalIdentity
    private let credentials: HouseholdCredentials?
    private let pairingCode: String?
    private let ephemeral: Curve25519.KeyAgreement.PrivateKey
    private let nonce: Data
    private var state = State.idle
    private var transcript = Data()
    private var sessionKeys: KeySchedule.SessionKeys?
    private var pairingKeys: KeySchedule.PairingKeys?
    public private(set) var peerHello: HelloBody?

    /// - Parameters:
    ///   - pairingCode: for the initiator, the code the person typed. For the
    ///     responder, the code of its open pairing window (nil when closed).
    public init(
        role: KeySchedule.Role, local: LocalIdentity, intent: HandshakeIntent,
        credentials: HouseholdCredentials?, pairingCode: String? = nil,
        ephemeral: Curve25519.KeyAgreement.PrivateKey = .init(),
        nonce: Data = HouseholdCredentials.randomKey()
    ) {
        self.role = role
        self.local = local
        self.intent = intent
        self.credentials = credentials
        self.pairingCode = pairingCode
        self.ephemeral = ephemeral
        self.nonce = nonce
    }

    public var isComplete: Bool { state == .done }

    /// The initiator's opening message. The responder waits.
    public mutating func start() throws -> [Step] {
        guard role == .initiator, state == .idle else { return [] }
        if intent == .session, credentials == nil { throw HandshakeError.noHousehold }
        state = .awaitingHello
        return [.send(try message(.hello, ownHello(intent: intent)))]
    }

    public mutating func receive(_ message: PeerMessage) throws -> [Step] {
        if message.type == .reject {
            throw HandshakeError.rejected(try message.content(RejectBody.self).reason)
        }
        switch (role, state, message.type) {
        case (.responder, .idle, .hello):
            return try respondToHello(message.content(HelloBody.self))
        case (.initiator, .awaitingHello, .hello):
            return try continueAfterHello(message.content(HelloBody.self))
        case (_, .awaitingAuth, .auth):
            return try finishSession(message.content(ProofBody.self).proof)
        case (.responder, .awaitingPairProof, .pairProof):
            return try grantPairing(message.content(ProofBody.self).proof)
        case (.initiator, .awaitingGrant, .pairGrant):
            return try acceptGrant(message.content(PairGrantBody.self))
        default:
            throw HandshakeError.unexpected(message.type)
        }
    }

    // MARK: Responder

    private mutating func respondToHello(_ hello: HelloBody) throws -> [Step] {
        guard hello.protocolVersion == Self.protocolVersion else { throw HandshakeError.unsupportedVersion }
        switch hello.intent {
        case .session:
            guard let credentials else { throw HandshakeError.noHousehold }
            guard hello.householdID == credentials.id else { throw HandshakeError.wrongHousehold }
        case .pair:
            guard pairingCode != nil, credentials != nil else { throw HandshakeError.pairingClosed }
        }
        peerHello = hello
        let mine = ownHello(intent: hello.intent)
        try deriveKeys(initiator: hello, responder: mine, peerKey: hello.ephemeralKey)
        state = hello.intent == .session ? .awaitingAuth : .awaitingPairProof
        return [.send(try message(.hello, mine))]
    }

    private mutating func grantPairing(_ proof: Data) throws -> [Step] {
        guard let keys = pairingKeys, let credentials, let peerHello else { throw HandshakeError.pairingClosed }
        guard KeySchedule.verify(proof, key: keys.auth, transcript: transcript, role: .initiator) else {
            throw HandshakeError.wrongCode
        }
        let grant = PairGrantBody(
            householdID: credentials.id, householdName: credentials.name,
            sealedKey: try KeySchedule.sealHousehold(credentials, with: keys.seal),
            proof: KeySchedule.proof(key: keys.auth, transcript: transcript, role: .responder)
        )
        state = .done
        return [.send(try message(.pairGrant, grant)), .admitted(peer: peerHello)]
    }

    // MARK: Initiator

    private mutating func continueAfterHello(_ hello: HelloBody) throws -> [Step] {
        guard hello.protocolVersion == Self.protocolVersion else { throw HandshakeError.unsupportedVersion }
        if intent == .session, hello.householdID != credentials?.id { throw HandshakeError.wrongHousehold }
        peerHello = hello
        try deriveKeys(initiator: ownHello(intent: intent), responder: hello, peerKey: hello.ephemeralKey)
        if let keys = sessionKeys {
            state = .awaitingAuth
            return [.send(try message(.auth, ProofBody(proof: KeySchedule.proof(key: keys.auth, transcript: transcript, role: .initiator))))]
        }
        guard let keys = pairingKeys else { throw HandshakeError.wrongCode }
        state = .awaitingGrant
        return [.send(try message(.pairProof, ProofBody(proof: KeySchedule.proof(key: keys.auth, transcript: transcript, role: .initiator))))]
    }

    private mutating func acceptGrant(_ grant: PairGrantBody) throws -> [Step] {
        guard let keys = pairingKeys, let peerHello else { throw HandshakeError.wrongCode }
        guard KeySchedule.verify(grant.proof, key: keys.auth, transcript: transcript, role: .responder) else {
            throw HandshakeError.badProof
        }
        let household = try KeySchedule.openHousehold(grant.sealedKey, with: keys.seal)
        guard household.id == grant.householdID else { throw HandshakeError.badProof }
        state = .done
        return [.joined(household, host: peerHello)]
    }

    // MARK: Shared

    private mutating func finishSession(_ proof: Data) throws -> [Step] {
        guard let keys = sessionKeys, let peerHello else { throw HandshakeError.badProof }
        guard KeySchedule.verify(proof, key: keys.auth, transcript: transcript, role: role.peer) else {
            throw HandshakeError.badProof
        }
        state = .done
        let channel = keys.channel(for: role)
        if role == .responder {
            let reply = ProofBody(proof: KeySchedule.proof(key: keys.auth, transcript: transcript, role: .responder))
            return [.send(try message(.auth, reply)), .established(channel, peer: peerHello)]
        }
        return [.established(channel, peer: peerHello)]
    }

    private mutating func deriveKeys(initiator: HelloBody, responder: HelloBody, peerKey: Data) throws {
        transcript = KeySchedule.transcript(initiator: initiator, responder: responder)
        let publicKey = try Curve25519.KeyAgreement.PublicKey(rawRepresentation: peerKey)
        let shared = try ephemeral.sharedSecretFromKeyAgreement(with: publicKey)
        switch initiator.intent {
        case .session:
            guard let credentials else { throw HandshakeError.noHousehold }
            sessionKeys = KeySchedule.sessionKeys(householdKey: credentials.key, sharedSecret: shared, transcript: transcript)
        case .pair:
            guard let pairingCode else { throw HandshakeError.pairingClosed }
            pairingKeys = KeySchedule.pairingKeys(code: pairingCode, sharedSecret: shared, transcript: transcript)
        }
    }

    private func ownHello(intent: HandshakeIntent) -> HelloBody {
        HelloBody(protocolVersion: Self.protocolVersion, deviceID: local.deviceID, name: local.name, kind: local.kind,
                  nonce: nonce, ephemeralKey: ephemeral.publicKey.rawRepresentation,
                  householdID: credentials?.id, intent: intent)
    }

    private func message<Body: Encodable>(_ type: PeerMessageType, _ body: Body) throws -> PeerMessage {
        try PeerMessage(type: type, sender: local.deviceID, content: body)
    }
}
