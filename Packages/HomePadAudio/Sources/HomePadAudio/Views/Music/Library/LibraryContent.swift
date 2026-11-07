import Foundation
import MusicKit

/// What the Library section shows for the music source in use: Apple Music's
/// library of the account on this iPad (or the synced library when MusicKit
/// cannot read it), Music Assistant's library, Spotify's saved music, or the demo.
@MainActor
enum LibraryContent {
    enum State {
        case loading
        /// Nothing to show, with why and what to do.
        case empty(String)
        case items([MusicTileItem])
    }

    static func state(_ kind: LibraryKind, _ media: AudioMediaService) -> State {
        switch media.musicSource {
        case .musicAssistant:
            let type = musicAssistantType(kind)
            guard let items = media.musicAssistant.library[type] else { return .loading }
            let playing = media.musicAssistant.activePlayer
            return found(items.map { MusicShelves.tile($0, media, playing: playing) }, kind, source: "Music Assistant")
        case .spotify:
            guard media.spotify.isReady else { return .empty("Set up Spotify in Settings, under Audio and AirPlay, to see your Spotify library here.") }
            guard let items = media.spotify.library[kind] else { return .loading }
            return found(items.map { SpotifyPages.tile($0, media, opensPage: true) }, kind, source: "Spotify")
        case .thisIPad:
            return thisIPad(kind, media)
        }
    }

    private static func thisIPad(_ kind: LibraryKind, _ media: AudioMediaService) -> State {
        if let library = media.memberMusic.shown { return MemberMusicTiles.state(kind, library, media) }
        if media.demo != nil { return .items(demo(kind, media)) }
        guard media.appleMusic.isAuthorized else {
            return .empty("Allow HomePad to use Media and Apple Music to see your library. Listen Now has a Connect button.")
        }
        let library = media.appleMusicLibrary
        if library.failed.contains(kind) {
            let synced = syncedLibrary(kind, media)
            return synced.isEmpty ? .empty("Your Apple Music library isn't available right now.") : .items(synced)
        }
        guard library.loaded.contains(kind) else { return .loading }
        return found(library.tiles(kind, media), kind, source: "your Apple Music library")
    }

    private static func found(_ items: [MusicTileItem], _ kind: LibraryKind, source: String) -> State {
        items.isEmpty ? .empty("No \(kind.title.lowercased()) in \(source) yet.") : .items(items)
    }

    /// Loads the list the first time it is shown.
    static func load(_ kind: LibraryKind, _ media: AudioMediaService) async {
        switch media.musicSource {
        case .musicAssistant: await media.musicAssistant.loadLibrary(musicAssistantType(kind))
        case .spotify: await media.spotify.loadLibrary(kind)
        case .thisIPad:
            if let library = media.memberMusic.shown { return await library.load(kind) }
            guard media.demo == nil, media.appleMusic.isAuthorized else { return }
            await media.appleMusicLibrary.load(kind)
        }
    }

    private static func musicAssistantType(_ kind: LibraryKind) -> MAMediaItem.MediaType {
        switch kind {
        case .playlists: .playlist
        case .albums: .album
        case .artists: .artist
        case .songs: .track
        }
    }

    /// The synced library through MediaPlayer, for when MusicKit's library requests fail. Tiles play.
    private static func syncedLibrary(_ kind: LibraryKind, _ media: AudioMediaService) -> [MusicTileItem] {
        let library = media.mediaLibrary
        let entries: [MediaLibraryBrowser.Entry] = switch kind {
        case .playlists: library.playlists
        case .albums: library.recentlyAdded
        case .artists: library.artists
        case .songs: []
        }
        return entries.map { entry in
            MusicTileItem(id: "\(entry.id)", title: entry.title, subtitle: entry.subtitle, libraryArtwork: entry.artwork,
                          systemImage: kind.systemImage, isRound: kind == .artists) {
                Task { await media.perform { try await media.playLibrary(entry) } }
            }
        }
    }

    private static func demo(_ kind: LibraryKind, _ media: AudioMediaService) -> [MusicTileItem] {
        let items: [MAMediaItem] = switch kind {
        case .playlists: DemoMusicCatalog.playlists
        case .albums: DemoMusicCatalog.albums
        case .artists: DemoMusicCatalog.artists
        case .songs: DemoMusicCatalog.trackItems
        }
        return items.map { DemoMusicPages.tile($0, media, opensPage: true) }
    }
}
