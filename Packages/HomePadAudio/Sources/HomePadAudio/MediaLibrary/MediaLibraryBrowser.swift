import Foundation
import HomePadCore
import MediaPlayer
import Observation

/// The music library synced to this iPad, through MediaPlayer's `MPMediaQuery`.
/// It needs only the Media and Apple Music permission, no MusicKit developer token,
/// so it keeps native playback working while the Apple Music catalog does not.
@MainActor
@Observable
final class MediaLibraryBrowser {
    /// One playlist, album or artist from the library.
    struct Entry: Identifiable {
        let id: MPMediaEntityPersistentID
        let title: String
        let subtitle: String?
        let artwork: MPMediaItemArtwork?
        let collection: MPMediaItemCollection
    }

    private(set) var authorization = MPMediaLibrary.authorizationStatus()
    private(set) var playlists: [Entry] = []
    private(set) var recentlyAdded: [Entry] = []
    private(set) var artists: [Entry] = []
    private(set) var isLoaded = false
    private let log = Log.make("Music")

    var isAuthorized: Bool { authorization == .authorized }
    var hasContent: Bool { !playlists.isEmpty || !recentlyAdded.isEmpty || !artists.isEmpty }

    /// Asks for library access the first time. Shares the Media and Apple Music permission with MusicKit.
    @discardableResult
    func requestAuthorization() async -> Bool {
        if authorization == .notDetermined {
            authorization = await withCheckedContinuation { continuation in
                MPMediaLibrary.requestAuthorization { continuation.resume(returning: $0) }
            }
        }
        return isAuthorized
    }

    /// Reads playlists, recently added albums and artists. Runs once per launch unless `force` is set.
    func load(force: Bool = false) {
        authorization = MPMediaLibrary.authorizationStatus()
        guard isAuthorized, force || !isLoaded else { return }
        let lists = MPMediaQuery.playlists().collections ?? []
        playlists = lists.prefix(30).compactMap { collection in
            guard let playlist = collection as? MPMediaPlaylist, !playlist.items.isEmpty else { return nil }
            return Entry(id: playlist.persistentID, title: playlist.name ?? "Playlist",
                         subtitle: "\(playlist.count) songs", artwork: playlist.representativeItem?.artwork, collection: playlist)
        }
        let albums = MPMediaQuery.albums().collections ?? []
        recentlyAdded = albums
            .sorted { ($0.representativeItem?.dateAdded ?? .distantPast) > ($1.representativeItem?.dateAdded ?? .distantPast) }
            .prefix(24)
            .compactMap(Self.albumEntry)
        artists = (MPMediaQuery.artists().collections ?? []).prefix(24).compactMap { collection in
            guard let item = collection.representativeItem, let name = item.albumArtist ?? item.artist else { return nil }
            return Entry(id: item.artistPersistentID, title: name, subtitle: "\(collection.count) songs",
                         artwork: item.artwork, collection: collection)
        }
        isLoaded = true
        log.info("Library: \(self.playlists.count) playlists, \(albums.count) albums")
    }

    /// The best library match for a spoken request: a playlist, album or artist by name, then songs.
    func bestMatch(for query: String) -> Entry? {
        guard isAuthorized else { return nil }
        let needle = query.lowercased()
        if let playlist = playlists.first(where: { $0.title.lowercased().contains(needle) }) { return playlist }
        for property in [MPMediaItemPropertyAlbumTitle, MPMediaItemPropertyArtist, MPMediaItemPropertyTitle] {
            let search = MPMediaQuery.songs()
            search.addFilterPredicate(MPMediaPropertyPredicate(value: query, forProperty: property, comparisonType: .contains))
            if let items = search.items, let first = items.first {
                return Entry(id: first.persistentID, title: first.title ?? query, subtitle: first.artist,
                             artwork: first.artwork, collection: MPMediaItemCollection(items: Array(items.prefix(100))))
            }
        }
        return nil
    }

    private static func albumEntry(_ collection: MPMediaItemCollection) -> Entry? {
        guard let item = collection.representativeItem else { return nil }
        return Entry(id: item.albumPersistentID, title: item.albumTitle ?? "Album",
                     subtitle: item.albumArtist ?? item.artist, artwork: item.artwork, collection: collection)
    }
}
