import CryptoKit
import Foundation
import HomePadCore

/// The shared secret that makes devices one household. Every paired HomePad,
/// iPhone and Mac holds the same 32-byte key. It lives in the keychain
/// (iCloud Keychain, so a second device on the same Apple Account joins automatically).
public struct HouseholdCredentials: Codable, Equatable, Sendable {
    /// Random and public. Advertised over Bonjour so devices can tell households apart.
    public var id: String
    public var name: String
    /// 32 random bytes. Never leaves the device except sealed during pairing.
    public var key: Data

    public init(id: String = UUID().uuidString, name: String, key: Data = HouseholdCredentials.randomKey()) {
        self.id = id
        self.name = name
        self.key = key
    }

    public static func randomKey() -> Data {
        SymmetricKey(size: .bits256).withUnsafeBytes { Data($0) }
    }

    private static let account = "connect.household"

    /// Reads the household from the keychain.
    public static func load(from keychain: KeychainStore) -> HouseholdCredentials? {
        guard let text = keychain.string(for: account) else { return nil }
        return try? JSONDecoder().decode(HouseholdCredentials.self, from: Data(text.utf8))
    }

    /// Saves (or with nil, forgets) the household.
    @discardableResult
    public static func save(_ credentials: HouseholdCredentials?, to keychain: KeychainStore) -> Bool {
        guard let credentials, let data = try? JSONEncoder().encode(credentials) else {
            return keychain.set(nil, for: account)
        }
        return keychain.set(String(decoding: data, as: UTF8.self), for: account)
    }
}
