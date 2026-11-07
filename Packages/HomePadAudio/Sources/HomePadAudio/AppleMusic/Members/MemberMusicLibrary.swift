import Foundation
import HomePadCore
import Observation

/// One member's own Apple Music, while Music shows it: what their encrypted
/// cache held, refreshed from the Apple Music API with their token. It lives
/// only while they are recognized here, and is dropped with everything it
/// holds in memory when they are not.
@MainActor
@Observable
final class MemberMusicLibrary {
    /// Why the library could not be read just now.
    enum Problem: Equatable {
        /// Apple turned the token down, and the person's phone has not sent a new one yet.
        case needsNewToken
        /// The Apple Music API could not be reached.
        case offline
        /// The API answered with an error.
        case unavailable
    }

    let memberID: UUID
    let memberName: String
    /// The link it was made for. A new token makes a new link, and a new library.
    let link: MemberMusicLink
    private(set) var snapshot: MemberMusicSnapshot
    private(set) var problem: Problem?
    /// What is being read now: "home", a `LibraryKind` raw value, or a playlist ID.
    private(set) var loading: Set<String> = []
    /// True once Listen Now has something to show: the cache had it, or the first read ended.
    private(set) var isHomeReady: Bool

    /// Nil while there is no working token. The cached library still shows.
    @ObservationIgnored private let api: AppleMusicAPI?
    @ObservationIgnored private let save: (MemberMusicSnapshot) -> Void
    @ObservationIgnored private let onRejected: () -> Void
    @ObservationIgnored private let log = Log.make("Music")

    /// How many items each library list reads, as for this iPad's library.
    static let listLimit = AppleMusicLibrary.limit
    /// How many songs of a playlist are read and played.
    static let playlistLimit = 300

    init(memberID: UUID, memberName: String, link: MemberMusicLink, snapshot: MemberMusicSnapshot, api: AppleMusicAPI?,
         save: @escaping (MemberMusicSnapshot) -> Void, onRejected: @escaping () -> Void) {
        self.memberID = memberID
        self.memberName = memberName
        self.link = link
        self.snapshot = snapshot
        self.api = api
        self.save = save
        self.onRejected = onRejected
        self.isHomeReady = snapshot.homeSavedAt != nil
        if api == nil || link.needsNewToken { problem = .needsNewToken }
    }

    /// "Kyle's Library".
    var libraryTitle: String { "\(memberName)'s Library" }

    // MARK: Reading

    /// Reads Listen Now's part: recently played, recommendations, playlists
    /// and albums (for Recently Added). Each request fails on its own.
    func refreshHome() async {
        guard let api, !loading.contains("home") else { return }
        loading.insert("home")
        defer {
            loading.remove("home")
            isHomeReady = true
        }
        async let storefront = attempt("storefront") { try await api.storefront() }
        async let recent = attempt("recently played") { try await api.recentlyPlayed() }
        async let recommendations = attempt("recommendations") { try await api.recommendations() }
        async let playlists = attempt("playlists") { try await api.library(.playlists, limit: Self.listLimit) }
        async let albums = attempt("albums") { try await api.library(.albums, limit: Self.listLimit) }
        let results = await (storefront, recent, recommendations, playlists, albums)
        if let found = results.0 { snapshot.storefront = found }
        if let found = results.1 { snapshot.recentlyPlayed = MemberMusicItem.list(found) }
        if let found = results.2 { snapshot.recommendations = found.compactMap(MemberMusicShelf.init) }
        if let found = results.3 { snapshot.set(MemberMusicItem.list(found), for: .playlists) }
        if let found = results.4 { snapshot.set(MemberMusicItem.list(found), for: .albums) }
        if results.1 != nil || results.2 != nil || results.3 != nil {
            snapshot.homeSavedAt = Date()
            problem = nil
        }
        save(snapshot)
    }

    /// Reads one library list, the first time it shows or again when `force` is set.
    func load(_ kind: LibraryKind, force: Bool = false) async {
        guard let api, force || !snapshot.isLoaded(kind), !loading.contains(kind.rawValue) else { return }
        loading.insert(kind.rawValue)
        defer { loading.remove(kind.rawValue) }
        guard let found = await attempt(kind.rawValue, { try await api.library(kind, limit: Self.listLimit) }) else { return }
        snapshot.set(MemberMusicItem.list(found), for: kind)
        problem = nil
        save(snapshot)
    }

    /// A playlist's songs: kept ones at once, else read from Apple. A catalog
    /// playlist (no library ID) has none here, since the catalog page lists it.
    func tracks(of playlist: MemberMusicItem) async -> [MemberMusicItem]? {
        if let kept = snapshot.playlistTracks[playlist.id], !loading.contains(playlist.id) {
            Task { await self.refreshTracks(of: playlist) }
            return kept
        }
        return await refreshTracks(of: playlist)
    }

    @discardableResult
    private func refreshTracks(of playlist: MemberMusicItem) async -> [MemberMusicItem]? {
        guard let api, playlist.isLibrary, !loading.contains(playlist.id) else { return snapshot.playlistTracks[playlist.id] }
        loading.insert(playlist.id)
        defer { loading.remove(playlist.id) }
        guard let found = await attempt("playlist", { try await api.playlistTracks(playlist.id, limit: Self.playlistLimit) }) else {
            return snapshot.playlistTracks[playlist.id]
        }
        let songs = MemberMusicItem.list(found).filter { $0.kind == .song }
        snapshot.keepTracks(songs, of: playlist.id)
        save(snapshot)
        return songs
    }

    /// The person's playlists, read first when they were not yet, for the assistant.
    func allPlaylists() async -> [MemberMusicItem] {
        await load(.playlists)
        return snapshot.playlists
    }

    /// Runs one request. A turned-down token is reported once, and the cached
    /// library keeps showing. The token and the reply are never logged.
    private func attempt<Value>(_ label: String, _ request: () async throws -> Value) async -> Value? {
        do {
            return try await request()
        } catch AppleMusicAPI.Failure.tokenRejected(let status) {
            log.error("Member Apple Music \(label, privacy: .public): token turned down (\(status))")
            if problem != .needsNewToken {
                problem = .needsNewToken
                onRejected()
            }
        } catch AppleMusicAPI.Failure.offline {
            if problem == nil { problem = .offline }
        } catch {
            log.error("Member Apple Music \(label, privacy: .public) failed: \(String(describing: error), privacy: .public)")
            if problem == nil { problem = .unavailable }
        }
        return nil
    }
}
