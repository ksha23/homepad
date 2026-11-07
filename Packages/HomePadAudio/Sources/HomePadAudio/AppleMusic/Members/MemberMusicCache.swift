import CryptoKit
import Foundation
import HomePadCore

/// What HomePad keeps of one member's own Apple Music between visits, so
/// Music shows it the moment they are recognized and refreshes behind it.
struct MemberMusicSnapshot: Codable, Equatable, Sendable {
    var storefront: String?
    var recentlyPlayed: [MemberMusicItem] = []
    var recommendations: [MemberMusicShelf] = []
    var playlists: [MemberMusicItem] = []
    var albums: [MemberMusicItem] = []
    var artists: [MemberMusicItem] = []
    var songs: [MemberMusicItem] = []
    /// The library lists read at least once, by `LibraryKind` raw value, so an
    /// empty list means empty rather than not read yet.
    var loadedKinds: Set<String> = []
    /// The songs of the playlists opened lately, by playlist ID.
    var playlistTracks: [String: [MemberMusicItem]] = [:]
    /// The playlists in `playlistTracks`, opened longest ago first.
    var playlistOrder: [String] = []
    /// When the Listen Now part was last read from Apple.
    var homeSavedAt: Date?

    /// How many playlists keep their songs.
    static let playlistTrackLimit = 20

    func items(_ kind: LibraryKind) -> [MemberMusicItem] {
        switch kind {
        case .playlists: playlists
        case .albums: albums
        case .artists: artists
        case .songs: songs
        }
    }

    mutating func set(_ items: [MemberMusicItem], for kind: LibraryKind) {
        switch kind {
        case .playlists: playlists = items
        case .albums: albums = items
        case .artists: artists = items
        case .songs: songs = items
        }
        loadedKinds.insert(kind.rawValue)
    }

    func isLoaded(_ kind: LibraryKind) -> Bool { loadedKinds.contains(kind.rawValue) }

    /// The albums added last, newest first, as Listen Now's Recently Added.
    var recentlyAdded: [MemberMusicItem] {
        let dated = albums.compactMap { album in album.addedDate.map { (album, $0) } }
        return dated.sorted { $0.1 > $1.1 }.prefix(24).map(\.0)
    }

    /// Keeps a playlist's songs, dropping the playlist opened longest ago when there are too many.
    mutating func keepTracks(_ tracks: [MemberMusicItem], of playlistID: String) {
        playlistTracks[playlistID] = tracks
        playlistOrder.removeAll { $0 == playlistID }
        playlistOrder.append(playlistID)
        while playlistOrder.count > Self.playlistTrackLimit {
            playlistTracks[playlistOrder.removeFirst()] = nil
        }
    }
}

/// Where the cache keeps its keys. The Keychain in the app, memory in tests.
protocol MemberMusicSecrets: Sendable {
    func string(for account: String) -> String?
    @discardableResult func set(_ value: String?, for account: String) -> Bool
}

extension KeychainStore: MemberMusicSecrets {}

/// On a HomePad: each member's own Apple Music listings, encrypted, the same
/// way Messages keeps each person's conversations (`CommsCache`).
///
/// Each member has a random 256-bit key in this iPad's Keychain (this device
/// only, never iCloud Keychain) and one AES-GCM sealed file. A copied file is
/// useless without that member's key, and `delete(member:)` removes both. It
/// holds names, artwork addresses and IDs, never the token.
struct MemberMusicCache: Sendable {
    private let directory: URL
    private let keychain: any MemberMusicSecrets

    init(directory: URL = MemberMusicCache.defaultDirectory,
         keychain: any MemberMusicSecrets = KeychainStore(service: "com.ksha23.homepad.music.cache", synchronizable: false,
                                                           thisDeviceOnly: true)) {
        self.directory = directory
        self.keychain = keychain
    }

    static var defaultDirectory: URL {
        URL.applicationSupportDirectory.appendingPathComponent("HomePadAudio/MemberMusic", isDirectory: true)
    }

    func load(member: UUID) -> MemberMusicSnapshot? {
        guard let key = existingKey(member), let sealed = try? Data(contentsOf: file(member)),
              let box = try? AES.GCM.SealedBox(combined: sealed),
              let plain = try? AES.GCM.open(box, using: key) else { return nil }
        return try? Self.decoder.decode(MemberMusicSnapshot.self, from: plain)
    }

    @discardableResult
    func save(_ snapshot: MemberMusicSnapshot, member: UUID) -> Bool {
        guard let key = key(member), let plain = try? Self.encoder.encode(snapshot),
              let sealed = try? AES.GCM.seal(plain, using: key).combined else { return false }
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try sealed.write(to: file(member), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            return true
        } catch {
            return false
        }
    }

    /// Removes the member's file and key. Without the key any leftover copy is noise.
    func delete(member: UUID) {
        try? FileManager.default.removeItem(at: file(member))
        keychain.set(nil, for: keyAccount(member))
    }

    /// Removes everyone not in `members`: people who left or whose Apple Music is no longer linked.
    func prune(keeping members: Set<UUID>) {
        for member in cachedMembers() where !members.contains(member) {
            delete(member: member)
        }
    }

    /// The members with a file here.
    func cachedMembers() -> [UUID] {
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        return files.compactMap { UUID(uuidString: $0.deletingPathExtension().lastPathComponent) }
    }

    // MARK: Plumbing

    private func file(_ member: UUID) -> URL { directory.appendingPathComponent("\(member.uuidString).sealed") }
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
