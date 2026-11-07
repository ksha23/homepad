import CommsKit
import CryptoKit
import Foundation
import HomePadCore

/// What is kept on disk for one person: enough to show their messages the instant
/// they appear, before the Mac has answered.
struct CacheSnapshot: Codable, Equatable {
    var conversations: [CommsConversation]
    var threads: [String: [CommsMessage]]
    /// The last hub event this snapshot includes, so a reconnect asks for only what came after.
    var lastEventID: Int?
    /// Which run of the hub `lastEventID` belongs to.
    var hubEpoch: Int?
    var savedAt: Date
    /// What the person has read on this iPad (`ReadMarkers`). Missing from caches saved before it existed.
    var readMarkers: ReadMarkers?
}

/// Where the cache keeps its keys. The Keychain in the app, memory in tests.
protocol SecretStore: Sendable {
    func string(for account: String) -> String?
    @discardableResult func set(_ value: String?, for account: String) -> Bool
}

extension KeychainStore: SecretStore {}

/// An encrypted, per-person copy of recent messages.
///
/// Each member has their own random 256-bit key in this iPad's Keychain (never iCloud
/// Keychain) and their own file, sealed with AES-GCM. A copy of the file without the
/// Keychain item is unreadable, and `delete(member:)` removes both.
struct CommsCache: Sendable {
    /// How much to keep, so the file stays small and fast to load.
    static let maxConversations = 25
    static let maxMessagesPerThread = 40

    private let directory: URL
    private let keychain: any SecretStore

    init(
        directory: URL = CommsCache.defaultDirectory,
        keychain: any SecretStore = KeychainStore(service: "com.homepad.comms.cache", synchronizable: false)
    ) {
        self.directory = directory
        self.keychain = keychain
    }

    static var defaultDirectory: URL {
        URL.applicationSupportDirectory.appendingPathComponent("HomePadComms", isDirectory: true)
    }

    func load(member: UUID) -> CacheSnapshot? {
        guard let key = existingKey(member), let sealed = try? Data(contentsOf: file(member)),
              let box = try? AES.GCM.SealedBox(combined: sealed),
              let plain = try? AES.GCM.open(box, using: key) else { return nil }
        return try? Self.decoder.decode(CacheSnapshot.self, from: plain)
    }

    @discardableResult
    func save(_ snapshot: CacheSnapshot, member: UUID) -> Bool {
        guard let key = key(member), let plain = try? Self.encoder.encode(trimmed(snapshot)),
              let sealed = try? AES.GCM.seal(plain, using: key).combined else { return false }
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try sealed.write(to: file(member), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            return true
        } catch {
            return false
        }
    }

    /// Removes the person's file and key. Without the key any leftover copy is noise.
    func delete(member: UUID) {
        try? FileManager.default.removeItem(at: file(member))
        keychain.set(nil, for: keyAccount(member))
    }

    // MARK: Plumbing

    private func trimmed(_ snapshot: CacheSnapshot) -> CacheSnapshot {
        let conversations = Array(snapshot.conversations.prefix(Self.maxConversations))
        let kept = Set(conversations.map(\.id))
        let threads = snapshot.threads
            .filter { kept.contains($0.key) }
            .mapValues { Array($0.suffix(Self.maxMessagesPerThread)) }
        // Markers are kept beyond the saved conversations, so a conversation further down the list stays read.
        return CacheSnapshot(
            conversations: conversations, threads: threads, lastEventID: snapshot.lastEventID, hubEpoch: snapshot.hubEpoch,
            savedAt: snapshot.savedAt, readMarkers: snapshot.readMarkers?.trimmed()
        )
    }

    private func file(_ member: UUID) -> URL { directory.appendingPathComponent("\(member.uuidString).cache") }
    private func keyAccount(_ member: UUID) -> String { "key.\(member.uuidString)" }

    private func existingKey(_ member: UUID) -> SymmetricKey? {
        guard let text = keychain.string(for: keyAccount(member)), let data = Data(base64Encoded: text) else { return nil }
        return SymmetricKey(data: data)
    }

    /// The person's key, made on first use.
    private func key(_ member: UUID) -> SymmetricKey? {
        if let existing = existingKey(member) { return existing }
        let fresh = SymmetricKey(size: .bits256)
        let text = fresh.withUnsafeBytes { Data($0).base64EncodedString() }
        return keychain.set(text, for: keyAccount(member)) ? fresh : nil
    }

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}
