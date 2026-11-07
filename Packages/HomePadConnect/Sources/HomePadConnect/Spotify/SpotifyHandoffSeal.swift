import CryptoKit
import Foundation

/// Seals a Spotify sign-in to one HomePad.
///
/// The peer link already seals every frame, but any household device holds
/// the household key and can open its own session saying it is the HomePad,
/// then pass the phone's messages on to the real one. So the sign-in gets a
/// seal of its own: the phone and the HomePad each make a one-time X25519 key,
/// the HomePad signs its half with its own key (`HomePadKey`), and the sign-in
/// is sealed with a key only those two halves make. A device in the middle
/// cannot swap in its own half without breaking the signature, so it never
/// reads the code.
enum SpotifyHandoffSeal {
    static func newAgreementKey() -> Curve25519.KeyAgreement.PrivateKey {
        Curve25519.KeyAgreement.PrivateKey()
    }

    /// The key both sides make: X25519, then HKDF-SHA256 salted with the
    /// exchange's nonces, so it fits this one exchange.
    static func key(privateKey: Curve25519.KeyAgreement.PrivateKey, peerKey: Data,
                    hello: SpotifyHello, homePadNonce: Data) throws -> SymmetricKey {
        let peer = try Curve25519.KeyAgreement.PublicKey(rawRepresentation: peerKey)
        let secret = try privateKey.sharedSecretFromKeyAgreement(with: peer)
        let salt = Data(hello.requestID.uuidString.utf8) + hello.nonce + homePadNonce
        return secret.hkdfDerivedSymmetricKey(using: SHA256.self, salt: salt,
                                              sharedInfo: Data("homepad.spotify.handoff.v1".utf8), outputByteCount: 32)
    }

    /// ChaChaPoly, with the request ID as associated data.
    static func seal(_ signIn: SpotifySignInCode, with key: SymmetricKey, requestID: UUID) throws -> Data {
        let plain = try JSONEncoder().encode(signIn)
        return try ChaChaPoly.seal(plain, using: key, authenticating: Data(requestID.uuidString.utf8)).combined
    }

    static func open(_ sealed: Data, with key: SymmetricKey, requestID: UUID) throws -> SpotifySignInCode {
        let box = try ChaChaPoly.SealedBox(combined: sealed)
        let plain = try ChaChaPoly.open(box, using: key, authenticating: Data(requestID.uuidString.utf8))
        return try JSONDecoder().decode(SpotifySignInCode.self, from: plain)
    }
}
