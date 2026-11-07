import CryptoKit
import Foundation
import LocalAuthentication
import Security

/// On a phone or Mac: the key that signs approvals.
///
/// Where there is a Secure Enclave the key is made inside it, and it signs
/// only after Face ID, Touch ID or the passcode (`.userPresence`), on a device
/// with a passcode. The simulator has no passcode, so there it is a software key.
/// Either way it stays on this device: the keychain item is this-device-only
/// and never syncs to iCloud or moves to another device in a backup.
@MainActor
enum DeviceApprovalKey {
    enum Failure: LocalizedError, Equatable {
        case noPasscode
        case cancelled
        case notVerified(String)
        case keyUnavailable

        var errorDescription: String? {
            switch self {
            case .noPasscode: "Set a passcode on this device to approve unlocks with it."
            case .cancelled: "Cancelled."
            case .notVerified(let reason): reason
            case .keyUnavailable: "This device could not make its approval key."
            }
        }
    }

    /// The public half, raw representation, made on first use.
    static func publicKey() throws -> Data {
        try Signer.loadOrCreate(context: nil).publicKey.rawRepresentation
    }

    /// Verifies the person with Face ID, Touch ID or the passcode, then signs.
    static func signApproval(_ data: Data, reason: String) async throws -> Data {
        let context = LAContext()
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            if error?.code == LAError.passcodeNotSet.rawValue { throw Failure.noPasscode }
            throw Failure.notVerified(error?.localizedDescription ?? "Face ID and the passcode are not available.")
        }
        do {
            _ = try await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason)
        } catch let laError as LAError where [.userCancel, .appCancel, .systemCancel].contains(laError.code) {
            throw Failure.cancelled
        } catch {
            throw Failure.notVerified(error.localizedDescription)
        }
        // The context just passed, so the Secure Enclave key signs without asking again.
        return try Signer.loadOrCreate(context: context).sign(data)
    }

    #if DEBUG
    /// Signs without Face ID, for the simulator, which has no passcode
    /// (`-ConnectApprovalSkipVerify YES`, debug builds only).
    static func signWithoutVerifying(_ data: Data) throws -> Data {
        try Signer.loadOrCreate(context: nil).sign(data)
    }
    #endif
}

/// The stored key, in the Secure Enclave or in software.
private enum Signer {
    case enclave(SecureEnclave.P256.Signing.PrivateKey)
    case software(P256.Signing.PrivateKey)

    var publicKey: P256.Signing.PublicKey {
        switch self {
        case .enclave(let key): key.publicKey
        case .software(let key): key.publicKey
        }
    }

    func sign(_ data: Data) throws -> Data {
        switch self {
        case .enclave(let key): try key.signature(for: data).rawRepresentation
        case .software(let key): try key.signature(for: data).rawRepresentation
        }
    }

    static func loadOrCreate(context: LAContext?) throws -> Signer {
        if let blob = ApprovalKeychain.read(.enclave) {
            return .enclave(try SecureEnclave.P256.Signing.PrivateKey(dataRepresentation: blob, authenticationContext: context))
        }
        if let raw = ApprovalKeychain.read(.software) {
            return .software(try P256.Signing.PrivateKey(rawRepresentation: raw))
        }
        if hasSecureEnclave {
            var error: Unmanaged<CFError>?
            guard let access = SecAccessControlCreateWithFlags(
                nil, kSecAttrAccessibleWhenPasscodeSetThisDeviceOnly, [.privateKeyUsage, .userPresence], &error
            ) else { throw DeviceApprovalKey.Failure.keyUnavailable }
            guard let key = try? SecureEnclave.P256.Signing.PrivateKey(accessControl: access, authenticationContext: context) else {
                // Making a key that needs the passcode fails on a device without one.
                throw DeviceApprovalKey.Failure.noPasscode
            }
            guard ApprovalKeychain.write(key.dataRepresentation, as: .enclave) else { throw DeviceApprovalKey.Failure.keyUnavailable }
            return .enclave(key)
        }
        let key = P256.Signing.PrivateKey()
        guard ApprovalKeychain.write(key.rawRepresentation, as: .software) else { throw DeviceApprovalKey.Failure.keyUnavailable }
        return .software(key)
    }

    /// The simulator can report a Secure Enclave, but it has no passcode, so
    /// a key that needs one cannot be made there.
    private static var hasSecureEnclave: Bool {
        #if targetEnvironment(simulator)
        false
        #else
        SecureEnclave.isAvailable
        #endif
    }
}

/// One keychain item per key kind: this device only, never synced.
private enum ApprovalKeychain {
    enum Item: String {
        /// The Secure Enclave's wrapped key, usable only by this device's enclave.
        case enclave = "approval.enclave"
        case software = "approval.software"
    }

    private static let service = "com.ksha23.homepad.approval"

    static func read(_ item: Item) -> Data? {
        var query = base(item)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess else { return nil }
        return result as? Data
    }

    static func write(_ data: Data, as item: Item) -> Bool {
        SecItemDelete(base(item) as CFDictionary)
        var attributes = base(item)
        attributes[kSecValueData as String] = data
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        return SecItemAdd(attributes as CFDictionary, nil) == errSecSuccess
    }

    private static func base(_ item: Item) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: item.rawValue,
            kSecAttrSynchronizable as String: kCFBooleanFalse as Any,
        ]
    }
}
