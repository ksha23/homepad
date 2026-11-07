import Foundation
import HomePadCore
import MusicKit
import Observation

/// The library section's four lists.
enum LibraryKind: String, CaseIterable, Identifiable, Sendable {
    case playlists, albums, artists, songs

    var id: String { rawValue }

    var title: String {
        switch self {
        case .playlists: "Playlists"
        case .albums: "Albums"
        case .artists: "Artists"
        case .songs: "Songs"
        }
    }

    var systemImage: String {
        switch self {
        case .playlists: "music.note.list"
        case .albums: "square.stack"
        case .artists: "music.mic"
        case .songs: "music.note"
        }
    }
}

/// The Apple Music library of the account signed in on this iPad: playlists by
/// last played, albums by date added, artists by name and songs by date added.
/// Each list loads the first time it is shown. MusicKit has one library per
/// iPad, so every household member sees the same one.
@MainActor
@Observable
final class AppleMusicLibrary {
    private(set) var playlists: [Playlist] = []
    private(set) var albums: [Album] = []
    private(set) var artists: [Artist] = []
    private(set) var songs: [Song] = []
    private(set) var loaded: Set<LibraryKind> = []
    private(set) var loading: Set<LibraryKind> = []
    /// Lists whose request failed, so the screen can say so instead of showing nothing.
    private(set) var failed: Set<LibraryKind> = []
    private let log = Log.make("Music")

    /// How many items each list loads. Enough to fill several screens.
    static let limit = 300

    /// Loads one list the first time, or again when `force` is set.
    func load(_ kind: LibraryKind, force: Bool = false) async {
        guard force || !loaded.contains(kind), !loading.contains(kind) else { return }
        loading.insert(kind)
        defer { loading.remove(kind) }
        do {
            switch kind {
            case .playlists:
                var request = MusicLibraryRequest<Playlist>()
                request.sort(by: \.lastPlayedDate, ascending: false)
                request.limit = Self.limit
                playlists = Array(try await request.response().items)
            case .albums:
                var request = MusicLibraryRequest<Album>()
                request.sort(by: \.libraryAddedDate, ascending: false)
                request.limit = Self.limit
                albums = Array(try await request.response().items)
            case .artists:
                var request = MusicLibraryRequest<Artist>()
                request.sort(by: \.name, ascending: true)
                request.limit = Self.limit
                artists = Array(try await request.response().items)
            case .songs:
                var request = MusicLibraryRequest<Song>()
                request.sort(by: \.libraryAddedDate, ascending: false)
                request.limit = Self.limit
                songs = Array(try await request.response().items)
            }
            failed.remove(kind)
            loaded.insert(kind)
        } catch {
            log.error("Library \(kind.rawValue, privacy: .public) failed: \(String(reflecting: error), privacy: .public)")
            failed.insert(kind)
        }
    }

    /// The tiles for one list. Albums, playlists and artists open their page.
    func tiles(_ kind: LibraryKind, _ media: AudioMediaService) -> [MusicTileItem] {
        switch kind {
        case .playlists: playlists.map { AppleMusicTiles.playlist($0, media, opensPage: true) }
        case .albums: albums.map { AppleMusicTiles.album($0, media, opensPage: true) }
        case .artists: artists.map { AppleMusicTiles.artist($0, media) }
        case .songs: songs.map { AppleMusicTiles.song($0, in: songs, media) }
        }
    }
}
