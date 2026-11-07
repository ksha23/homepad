import Foundation

/// Why a device wants to talk.
public enum HandshakeIntent: String, Codable, Sendable {
    /// Normal traffic between members of the same household.
    case session
    /// A new device joining with the 6-digit code.
    case pair
}

/// First message from each side. Sent in the clear.
public struct HelloBody: Codable, Equatable, Sendable {
    public var protocolVersion: Int
    public var deviceID: String
    public var name: String
    public var kind: DeviceKind
    /// 32 random bytes, mixed into every derived key.
    public var nonce: Data
    /// Ephemeral X25519 public key, so keys are never derivable from a recording.
    public var ephemeralKey: Data
    /// Household the sender belongs to, if any. Not secret.
    public var householdID: String?
    public var intent: HandshakeIntent
}

/// HMAC proof that the sender holds the household key (or the pairing code).
public struct ProofBody: Codable, Equatable, Sendable {
    public var proof: Data
}

/// The host's answer to a correct pairing code: the household key, sealed
/// with a key only the code holder can derive, plus the host's own proof.
public struct PairGrantBody: Codable, Equatable, Sendable {
    public var householdID: String
    public var householdName: String
    public var sealedKey: Data
    public var proof: Data
}

/// Sent before closing when a handshake fails.
public struct RejectBody: Codable, Equatable, Sendable {
    public enum Reason: String, Codable, Sendable {
        case wrongHousehold, badProof, pairingClosed, wrongCode, tooManyAttempts, unsupportedVersion
    }
    public var reason: Reason
}
