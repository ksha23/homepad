import CryptoKit
import Foundation
import HomePadCore

/// On a HomePad: its own P256 signing key. The HomePad gives the public half
/// to each phone that links to it (`ApprovalLinkState.homePadKey`), and the
/// phone keeps it. A phone sends its photos only after the HomePad signs a
/// fresh challenge with this key, so another household device that says it
/// is this HomePad cannot ask for them.
///
/// It is a software key in this iPad's Keychain, never synced to iCloud
/// Keychain. An iPad has no use for user presence here, since the HomePad
/// signs whenever the recognized person's phone answers.
struct HomePadKey {
    /// Raw representation of the public key.
    let publicKey: Data
    let sign: (Data) throws -> Data

    init(_ key: P256.Signing.PrivateKey) {
        publicKey = key.publicKey.rawRepresentation
        sign = { try key.signature(for: $0).rawRepresentation }
    }

    /// The key kept in this iPad's Keychain, made on first use. Nil only when
    /// the Keychain refuses to store it.
    static func stored(in keychain: KeychainStore = KeychainStore(service: "com.ksha23.homepad.identity", synchronizable: false)) -> HomePadKey? {
        let account = "homepad.signing"
        if let text = keychain.string(for: account), let raw = Data(base64Encoded: text),
           let key = try? P256.Signing.PrivateKey(rawRepresentation: raw) {
            return HomePadKey(key)
        }
        let key = P256.Signing.PrivateKey()
        guard keychain.set(key.rawRepresentation.base64EncodedString(), for: account) else { return nil }
        return HomePadKey(key)
    }

    /// True when `signature` is the signature of the key `publicKey` names over `data`.
    static func isValid(_ signature: Data, of data: Data, by publicKey: Data) -> Bool {
        guard let key = try? P256.Signing.PublicKey(rawRepresentation: publicKey),
              let signature = try? P256.Signing.ECDSASignature(rawRepresentation: signature) else { return false }
        return key.isValidSignature(signature, for: data)
    }
}
