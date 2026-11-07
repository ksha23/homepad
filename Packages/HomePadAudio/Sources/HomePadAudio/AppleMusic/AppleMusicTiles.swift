import Foundation
import MusicKit

/// Tiles and menus for Apple Music items, shared by Listen Now, Search, the
/// Library and the album, playlist and artist pages.
///
/// Albums, playlists and artists open their page when `opensPage` is true
/// (Search and the Library, as in the Music app) and play at once otherwise
/// (Listen Now, which is made for a quick tap from across the room). Their
/// menu offers whichever of the two the tap does not, plus Play Next and Play Later.
@MainActor
enum AppleMusicTiles {
    static func album(_ album: Album, _ media: AudioMediaService, opensPage: Bool) -> MusicTileItem {
        let page = MusicPage.appleMusicAlbum(album)
        return MusicTileItem(id: album.id.rawValue, title: album.title, subtitle: album.artistName,
                             artwork: album.artwork, systemImage: "square.stack") {
            if opensPage { media.pages.push(page) } else { Task { await media.playMusic(album) } }
        }
        .with(collectionMenu(album, page: opensPage ? nil : page, openTitle: "Show Album", media))
    }

    static func playlist(_ playlist: Playlist, _ media: AudioMediaService, opensPage: Bool) -> MusicTileItem {
        let page = MusicPage.appleMusicPlaylist(playlist)
        return MusicTileItem(id: playlist.id.rawValue, title: playlist.name, subtitle: playlist.curatorName,
                             artwork: playlist.artwork, systemImage: "music.note.list") {
            if opensPage { media.pages.push(page) } else { Task { await media.playMusic(playlist) } }
        }
        .with(collectionMenu(playlist, page: opensPage ? nil : page, openTitle: "Show Playlist", media))
    }

    /// Artists always open their page. Their menu plays their top songs.
    static func artist(_ artist: Artist, _ media: AudioMediaService) -> MusicTileItem {
        var menu = MusicItemMenu()
        menu.play = { Task { await media.playArtist(artist) } }
        menu.shuffle = { Task { await media.playArtist(artist, shuffled: true) } }
        return MusicTileItem(id: artist.id.rawValue, title: artist.name, subtitle: nil, artwork: artist.artwork,
                             systemImage: "music.mic", isRound: true, menu: menu) {
            media.pages.push(.appleMusicArtist(artist))
        }
    }

    /// Stations play at once: they have no page and cannot be queued.
    static func station(_ station: Station, _ media: AudioMediaService) -> MusicTileItem {
        MusicTileItem(id: station.id.rawValue, title: station.name, subtitle: "Apple Music Radio",
                      artwork: station.artwork, systemImage: "dot.radiowaves.left.and.right") {
            Task { await media.playMusic(station) }
        }
    }

    /// A song that plays with the songs around it in `list`, like a search's song list.
    static func song(_ song: Song, in list: [Song], _ media: AudioMediaService) -> MusicTileItem {
        MusicTileItem(id: song.id.rawValue, title: song.title, subtitle: song.artistName, artwork: song.artwork) {
            Task { await media.playSongs(list, startingAt: song, recent: .appleMusic(song)) }
        }
        .with(songMenu(song, media))
    }

    // MARK: Menus

    /// Play or open, Shuffle, Play Next, Play Later and Add to Library for an album or playlist.
    static func collectionMenu<Item: PlayableMusicItem & MusicLibraryAddable>(
        _ item: Item, page: MusicPage?, openTitle: String, _ media: AudioMediaService
    ) -> MusicItemMenu {
        var menu = MusicItemMenu()
        if let page {
            menu.open = { media.pages.push(page) }
            menu.openTitle = openTitle
            menu.openSystemImage = openTitle == "Show Playlist" ? "music.note.list" : "square.stack"
        } else {
            menu.play = { Task { await media.playMusic(item) } }
        }
        menu.shuffle = { Task { await media.playMusic(item, shuffled: true) } }
        addQueueActions(to: &menu, items: [item], recent: .appleMusic(item), media)
        if isCatalog(item.id) { menu.addToLibrary = { Task { await media.addToLibrary(item) } } }
        return menu
    }

    /// Play Next, Play Later, Add to Library and Show Album for a song.
    static func songMenu(_ song: Song, _ media: AudioMediaService, showsAlbum: Bool = true) -> MusicItemMenu {
        var menu = MusicItemMenu()
        addQueueActions(to: &menu, items: [song], recent: .appleMusic(song), media)
        if isCatalog(song.id) { menu.addToLibrary = { Task { await media.addToLibrary(song) } } }
        if showsAlbum {
            menu.open = { Task { await media.openAlbum(of: song) } }
        }
        return menu
    }

    /// Play Next and Play Later, unless a station plays (MusicKit ignores songs queued with one).
    static func addQueueActions(to menu: inout MusicItemMenu, items: [any PlayableMusicItem],
                                recent: RecentMusicItem?, _ media: AudioMediaService) {
        guard !items.isEmpty, media.canQueueAppleMusic else { return }
        menu.playNext = { Task { await media.enqueue(appleMusic: items, at: .next, recent: recent) } }
        menu.playLater = { Task { await media.enqueue(appleMusic: items, at: .later, recent: recent) } }
    }

    /// Catalog IDs are numbers. Library IDs start with a letter and a dot ("l.", "i.", "p.", "r.").
    nonisolated static func isCatalog(_ id: MusicItemID) -> Bool {
        !id.rawValue.isEmpty && id.rawValue.allSatisfy(\.isNumber)
    }
}

extension AudioMediaService {
    /// Opens the album a song comes from.
    func openAlbum(of song: Song) async {
        await perform {
            let full = try await song.with([.albums])
            guard let album = full.albums?.first else { throw AudioError.nothingFound(song.albumTitle ?? song.title) }
            pages.push(.appleMusicAlbum(album))
        }
    }
}
