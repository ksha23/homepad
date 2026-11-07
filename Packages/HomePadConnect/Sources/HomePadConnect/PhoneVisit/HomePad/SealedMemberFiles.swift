import CryptoKit
import Foundation
import HomePadCore

/// On a HomePad: one folder per member of AES-GCM sealed files, the way
/// Messages keeps each person's conversations (`CommsCache`). Each kind of a
/// phone visit keeps its cache in its own folder with its own keys.
///
/// Each member has a random 256-bit key in this iPad's Keychain (never iCloud
/// Keychain). A copied file is useless without that member's key, and
/// `delete(member:)` removes the key and the folder.
struct SealedMemberFiles: Sendable {
    let directory: URL
    private let keychain: any SecretStore

    init(directory: URL, keychain: any SecretStore) {
        self.directory = directory
        self.keychain = keychain
    }

    func folder(_ member: UUID) -> URL { directory.appendingPathComponent(member.uuidString, isDirectory: true) }

    /// The file's contents, nil when it is missing or does not open with the member's key.
    func open(_ name: String, member: UUID) -> Data? {
        guard let key = existingKey(member), let sealed = try? Data(contentsOf: folder(member).appendingPathComponent(name)),
              let box = try? AES.GCM.SealedBox(combined: sealed) else { return nil }
        return try? AES.GCM.open(box, using: key)
    }

    /// Seals and writes a file, making the member's key on first use.
    @discardableResult
    func seal(_ plain: Data, as name: String, member: UUID) -> Bool {
        guard let key = key(member), let sealed = try? AES.GCM.seal(plain, using: key).combined else { return false }
        let file = folder(member).appendingPathComponent(name)
        do {
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try sealed.write(to: file, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            return true
        } catch {
            return false
        }
    }

    /// Removes one file of a member.
    func remove(_ name: String, member: UUID) {
        try? FileManager.default.removeItem(at: folder(member).appendingPathComponent(name))
    }

    /// Removes the member's key and folder. Without the key any leftover copy is noise.
    func delete(member: UUID) {
        try? FileManager.default.removeItem(at: folder(member))
        keychain.set(nil, for: keyAccount(member))
    }

    /// Removes everyone not in `members`, for people removed from the household.
    func prune(keeping members: Set<UUID>) {
        let folders = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        for folder in folders {
            guard let member = UUID(uuidString: folder.lastPathComponent), !members.contains(member) else { continue }
            delete(member: member)
        }
    }

    private func keyAccount(_ member: UUID) -> String { "key.\(member.uuidString)" }

    private func existingKey(_ member: UUID) -> SymmetricKey? {
        guard let text = keychain.string(for: keyAccount(member)), let data = Data(base64Encoded: text) else { return nil }
        return SymmetricKey(data: data)
    }

    /// The member's key, made on first use.
    private func key(_ member: UUID) -> SymmetricKey? {
        if let existing = existingKey(member) { return existing }
        let fresh = SymmetricKey(size: .bits256)
        let text = fresh.withUnsafeBytes { Data($0).base64EncodedString() }
        return keychain.set(text, for: keyAccount(member)) ? fresh : nil
    }
}

/// Where sealed folders keep their keys. The Keychain in the app, memory in tests.
protocol SecretStore: Sendable {
    func string(for account: String) -> String?
    @discardableResult func set(_ value: String?, for account: String) -> Bool
}

extension KeychainStore: SecretStore {}
