import Foundation
import HomePadCore
@testable import HomePadComms

/// The unit-test host has no Keychain access, so keys live in memory here.
final class MemorySecrets: SecretStore, @unchecked Sendable {
    private var values: [String: String] = [:]
    private let lock = NSLock()
    func string(for account: String) -> String? { lock.lock(); defer { lock.unlock() }; return values[account] }
    func set(_ value: String?, for account: String) -> Bool { lock.lock(); defer { lock.unlock() }; values[account] = value; return true }
}
