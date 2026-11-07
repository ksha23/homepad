import Foundation
import HomePadCore

/// Where a member's hub is and the token that opens it.
public struct HubCredentials: Codable, Equatable, Sendable {
    public var baseURL: URL
    public var token: String

    public init(baseURL: URL, token: String) {
        self.baseURL = baseURL
        self.token = token
    }
}

/// Per-member hub credentials. They live in this iPad's Keychain only (never
/// iCloud Keychain), under the member's ID, so nothing else can read them.
public struct HubCredentialStore: Sendable {
    private let keychain: KeychainStore

    public init(keychain: KeychainStore = KeychainStore(service: "com.homepad.comms", synchronizable: false)) {
        self.keychain = keychain
    }

    public func credentials(for member: UUID) -> HubCredentials? {
        guard let raw = keychain.string(for: account(member)), let data = raw.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(HubCredentials.self, from: data)
    }

    @discardableResult
    public func save(_ credentials: HubCredentials?, for member: UUID) -> Bool {
        guard let credentials else { return keychain.set(nil, for: account(member)) }
        guard let data = try? JSONEncoder().encode(credentials) else { return false }
        return keychain.set(String(decoding: data, as: UTF8.self), for: account(member))
    }

    private func account(_ member: UUID) -> String { "hub.\(member.uuidString)" }
}
