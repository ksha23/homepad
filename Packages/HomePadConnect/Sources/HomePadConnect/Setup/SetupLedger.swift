import Foundation
import HomePadCore

/// What one HomePad holds of the household's shared setup: every document at
/// the version it last saw, the household it shares with, and the HomePads it
/// synced with. The documents are the shared copies, so this HomePad can
/// answer for any version it holds even while its own copy is one of this
/// iPad's own (a photo wallpaper).
struct SetupLedger: Equatable, Sendable {
    var documents: [SetupKey: SetupDocument] = [:]
    /// The household whose setup this HomePad shares. Nil until it first syncs
    /// with another HomePad of its household, and different after it joins
    /// another household, which it then joins as a newcomer.
    var householdID: String?
    /// The HomePads it synced with, by device ID.
    var peers: [String: SetupPeer] = [:]
}

/// A HomePad this one synced with, for the status in Settings.
struct SetupPeer: Codable, Equatable, Sendable {
    var name: String
    var lastSync: Date
}

extension SetupLedger: Codable {
    private enum CodingKeys: String, CodingKey { case documents, householdID, peers }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let list = try container.decodeIfPresent([SetupDocument].self, forKey: .documents) ?? []
        documents = Dictionary(list.map { ($0.key, $0) }, uniquingKeysWith: SetupMerge.winner)
        householdID = try container.decodeIfPresent(String.self, forKey: .householdID)
        peers = try container.decodeIfPresent([String: SetupPeer].self, forKey: .peers) ?? [:]
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(documents.values.sorted { $0.key < $1.key }, forKey: .documents)
        try container.encodeIfPresent(householdID, forKey: .householdID)
        try container.encode(peers, forKey: .peers)
    }
}

/// Saves the ledger as one JSON file in Application Support. It holds no face
/// data and no secrets, only what every HomePad of the household shows.
struct SetupLedgerFile: Sendable {
    /// Nil keeps the ledger in memory, for tests.
    let url: URL?

    static func standard() -> SetupLedgerFile {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        return SetupLedgerFile(url: support?.appendingPathComponent("HomePadConnect/HouseholdSetup.json"))
    }

    func load() -> SetupLedger {
        guard let url, let data = try? Data(contentsOf: url),
              let ledger = try? PeerCoding.decoder().decode(SetupLedger.self, from: data) else { return SetupLedger() }
        return ledger
    }

    func save(_ ledger: SetupLedger) throws {
        guard let url else { return }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try PeerCoding.encoder().encode(ledger).write(to: url, options: .atomic)
    }
}
