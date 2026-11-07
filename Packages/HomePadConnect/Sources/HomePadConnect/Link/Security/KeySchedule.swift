import CryptoKit
import Foundation

/// Every key the peer link uses, derived with HKDF-SHA256 from:
/// - an ephemeral X25519 agreement (fresh per connection, so a recording of
///   the traffic cannot be decrypted later), and
/// - the household key (normal sessions) or the 6-digit code (pairing),
/// salted with the handshake transcript so keys are bound to this exact exchange.
///
/// Proofs are HMAC-SHA256 over the transcript plus the sender's role, so a
/// proof can never be reflected back at its author.
public enum KeySchedule {
    public enum Role: String, Sendable {
        case initiator = "I"
        case responder = "R"

        var peer: Role { self == .initiator ? .responder : .initiator }
    }

    /// Keys for an authenticated session.
    public struct SessionKeys {
        public let auth: SymmetricKey
        public let initiatorToResponder: SymmetricKey
        public let responderToInitiator: SymmetricKey

        /// The channel as seen from one side.
        public func channel(for role: Role) -> SecureChannel {
            role == .initiator
                ? SecureChannel(sendKey: initiatorToResponder, receiveKey: responderToInitiator)
                : SecureChannel(sendKey: responderToInitiator, receiveKey: initiatorToResponder)
        }
    }

    /// Keys for one pairing attempt.
    public struct PairingKeys {
        public let auth: SymmetricKey
        public let seal: SymmetricKey
    }

    static let label = "homepad.link.v1"

    /// Binds both hellos into one byte string. Order is fixed (initiator first).
    public static func transcript(initiator: HelloBody, responder: HelloBody) -> Data {
        var data = Data(label.utf8)
        for hello in [initiator, responder] {
            data.append(Data(hello.deviceID.utf8))
            data.append(0)
            data.append(hello.nonce)
            data.append(hello.ephemeralKey)
            data.append(Data(hello.intent.rawValue.utf8))
            data.append(0)
        }
        return Data(SHA256.hash(data: data))
    }

    public static func sessionKeys(householdKey: Data, sharedSecret: SharedSecret, transcript: Data) -> SessionKeys {
        let ikm = SymmetricKey(data: secretBytes(sharedSecret) + householdKey)
        return SessionKeys(
            auth: derive(ikm, salt: transcript, info: "session.auth"),
            initiatorToResponder: derive(ikm, salt: transcript, info: "session.i2r"),
            responderToInitiator: derive(ikm, salt: transcript, info: "session.r2i")
        )
    }

    public static func pairingKeys(code: String, sharedSecret: SharedSecret, transcript: Data) -> PairingKeys {
        let ikm = SymmetricKey(data: secretBytes(sharedSecret) + Data(code.utf8))
        return PairingKeys(
            auth: derive(ikm, salt: transcript, info: "pair.auth"),
            seal: derive(ikm, salt: transcript, info: "pair.seal")
        )
    }

    public static func proof(key: SymmetricKey, transcript: Data, role: Role) -> Data {
        Data(HMAC<SHA256>.authenticationCode(for: transcript + Data(role.rawValue.utf8), using: key))
    }

    /// Constant-time check of a proof made by `role`.
    public static func verify(_ proof: Data, key: SymmetricKey, transcript: Data, role: Role) -> Bool {
        HMAC<SHA256>.isValidAuthenticationCode(proof, authenticating: transcript + Data(role.rawValue.utf8), using: key)
    }

    /// Seals the household key and ID for a newly paired device.
    public static func sealHousehold(_ credentials: HouseholdCredentials, with key: SymmetricKey) throws -> Data {
        let plaintext = try JSONEncoder().encode(credentials)
        return try ChaChaPoly.seal(plaintext, using: key).combined
    }

    public static func openHousehold(_ sealed: Data, with key: SymmetricKey) throws -> HouseholdCredentials {
        let plaintext = try ChaChaPoly.open(ChaChaPoly.SealedBox(combined: sealed), using: key)
        return try JSONDecoder().decode(HouseholdCredentials.self, from: plaintext)
    }

    private static func derive(_ ikm: SymmetricKey, salt: Data, info: String) -> SymmetricKey {
        HKDF<SHA256>.deriveKey(inputKeyMaterial: ikm, salt: salt, info: Data("\(label).\(info)".utf8), outputByteCount: 32)
    }

    private static func secretBytes(_ secret: SharedSecret) -> Data {
        secret.withUnsafeBytes { Data($0) }
    }
}
