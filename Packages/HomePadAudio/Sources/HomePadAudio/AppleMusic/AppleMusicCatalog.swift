import Foundation
import HomePadCore
import MusicKit
import Observation

/// Browsing Apple Music: personal recommendations, recently played, library
/// playlists and catalog search. Playback goes through `AppleMusicPlayer`.
@MainActor
@Observable
final class AppleMusicCatalog {
    /// The live status from `AppleMusicProbe`, shown in the Music app and Settings.
    private(set) var status: AppleMusicStatus = .checking
    private(set) var recommendations: [MusicPersonalRecommendation] = []
    private(set) var recentlyPlayed: [RecentlyPlayedMusicItem] = []
    private(set) var playlists: [Playlist] = []
    private(set) var recentlyAdded: [Album] = []
    private(set) var searchResults: MusicCatalogSearchResponse?
    private(set) var isLoading = false
    /// The browse page loaded at least once (each request may still have failed).
    private(set) var hasLoadedHome = false
    private(set) var lastError: String?
    @ObservationIgnored private var statusCheckedAt: Date?
    private let log = Log.make("Music")

    /// - Parameter isDemo: Simulator screenshots report Ready without asking MusicKit.
    init(isDemo: Bool = false) {
        if isDemo {
            status = .ready
            statusCheckedAt = .distantFuture
        }
    }

    /// Runs the live probe again, at most once a minute unless `force` is set.
    func refreshStatus(force: Bool = false) async {
        if !force, let checked = statusCheckedAt, Date().timeIntervalSince(checked) < 60, status != .checking { return }
        statusCheckedAt = Date()
        status = await AppleMusicProbe.run()
    }

    /// Loads the browse page. Call only after authorization. Each request fails on its
    /// own and is logged, so one failure never blanks the page.
    func loadHome() async {
        isLoading = true
        defer { isLoading = false }
        async let recommendations = attempt("Recommendations") { try await MusicPersonalRecommendationsRequest().response().recommendations }
        async let recent = attempt("Recently played") { try await MusicRecentlyPlayedRequest<RecentlyPlayedMusicItem>().response().items }
        async let library = attempt("Library playlists") { try await MusicLibraryRequest<Playlist>().response().items }
        async let added = attempt("Recently added") {
            var request = MusicLibraryRequest<Album>()
            request.sort(by: \.libraryAddedDate, ascending: false)
            request.limit = 24
            return try await request.response().items
        }
        let (recs, recents, lists, albums) = await (recommendations, recent, library, added)
        self.recommendations = recs.map(Array.init) ?? []
        recentlyPlayed = recents.map(Array.init) ?? []
        playlists = lists.map(Array.init) ?? []
        recentlyAdded = albums.map(Array.init) ?? []
        lastError = (recs == nil && recents == nil && lists == nil && albums == nil) ? "Apple Music isn't reachable right now." : nil
        hasLoadedHome = true
    }

    /// Runs one MusicKit request and logs the exact error when it fails.
    private func attempt<Value>(_ label: String, _ request: () async throws -> Value) async -> Value? {
        do {
            return try await request()
        } catch {
            log.error("\(label, privacy: .public) failed: \(String(reflecting: error), privacy: .public)")
            return nil
        }
    }

    func search(_ term: String) async {
        let query = term.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            searchResults = nil
            return
        }
        isLoading = true
        defer { isLoading = false }
        do {
            var request = MusicCatalogSearchRequest(term: query, types: [Song.self, Album.self, Playlist.self, Station.self, Artist.self])
            request.limit = 12
            request.includeTopResults = true
            searchResults = try await request.response()
            lastError = nil
        } catch {
            log.error("Search failed: \(String(reflecting: error), privacy: .public)")
            lastError = "Search isn't available right now."
        }
    }

    /// The single best thing to play for a spoken request such as "jazz for cooking".
    static func bestChoice(for term: String) async throws -> MusicChoice {
        var request = MusicCatalogSearchRequest(term: term, types: [Song.self, Album.self, Playlist.self, Station.self, Artist.self])
        request.limit = 10
        request.includeTopResults = true
        let response = try await request.response()
        let lowered = term.lowercased()
        if lowered.contains("playlist"), let playlist = response.playlists.first { return .playlist(playlist) }
        if lowered.contains("station") || lowered.contains("radio"), let station = response.stations.first { return .station(station) }
        for result in response.topResults {
            switch result {
            case .song(let song): return .songs(Array(response.songs), start: song)
            case .album(let album): return .album(album)
            case .playlist(let playlist): return .playlist(playlist)
            case .artist(let artist):
                let songs = response.songs.filter { $0.artistName.localizedCaseInsensitiveContains(artist.name) }
                if let first = songs.first { return .songs(Array(songs), start: first) }
            default:
                continue
            }
        }
        if let playlist = response.playlists.first { return .playlist(playlist) }
        if let song = response.songs.first { return .songs(Array(response.songs), start: song) }
        if let station = response.stations.first { return .station(station) }
        throw AudioError.nothingFound(term)
    }
}

/// Something from Apple Music the assistant decided to play.
enum MusicChoice {
    case songs([Song], start: Song)
    case album(Album)
    case playlist(Playlist)
    case station(Station)

    var title: String {
        switch self {
        case .songs(_, let start): "“\(start.title)” by \(start.artistName)"
        case .album(let album): "\(album.title) by \(album.artistName)"
        case .playlist(let playlist): "the playlist \(playlist.name)"
        case .station(let station): station.name
        }
    }

    /// What goes in Recently Played: the album, playlist or station, or the first song.
    var recent: RecentMusicItem? {
        switch self {
        case .songs(_, let start): .appleMusic(start)
        case .album(let album): .appleMusic(album)
        case .playlist(let playlist): .appleMusic(playlist)
        case .station(let station): .appleMusic(station)
        }
    }

    @MainActor
    func play(with player: AppleMusicPlayer) async throws {
        switch self {
        case .songs(let songs, let start): try await player.play(songs, startingAt: start)
        case .album(let album): try await player.play(album)
        case .playlist(let playlist): try await player.play(playlist)
        case .station(let station): try await player.play(station)
        }
    }
}
