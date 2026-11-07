import Foundation
import Security

/// Secrets storage (AI provider API keys, Home Assistant tokens).
/// With `synchronizable` the item rides iCloud Keychain to the user's other
/// devices, so entering a key once on the iPhone companion fills every HomePad.
/// With `thisDeviceOnly` the item never leaves this device: it does not sync,
/// and a backup restored to another device does not bring it back.
public struct KeychainStore: Sendable {
    public let service: String
    public let synchronizable: Bool
    public let thisDeviceOnly: Bool

    public init(service: String = "com.homepad.secrets", synchronizable: Bool = true, thisDeviceOnly: Bool = false) {
        self.service = service
        // An item kept to this device cannot sync, so the Keychain would refuse the pair.
        self.synchronizable = synchronizable && !thisDeviceOnly
        self.thisDeviceOnly = thisDeviceOnly
    }

    public func string(for account: String) -> String? {
        var query = baseQuery(account: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    @discardableResult
    public func set(_ value: String?, for account: String) -> Bool {
        let query = baseQuery(account: account)
        SecItemDelete(query as CFDictionary)
        guard let value, !value.isEmpty else { return true }
        var attributes = query
        attributes[kSecValueData as String] = Data(value.utf8)
        attributes[kSecAttrAccessible as String] = thisDeviceOnly
            ? kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly : kSecAttrAccessibleAfterFirstUnlock
        return SecItemAdd(attributes as CFDictionary, nil) == errSecSuccess
    }

    public func has(_ account: String) -> Bool {
        string(for: account) != nil
    }

    private func baseQuery(account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrSynchronizable as String: synchronizable ? kCFBooleanTrue as Any : kCFBooleanFalse as Any,
        ]
    }
}
