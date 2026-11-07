import Foundation
import MusicKit

/// Album, playlist and artist pages for Apple Music, from the catalog or the
/// library of the account on this iPad.
@MainActor
enum AppleMusicPages {
    static func detail(_ page: MusicPage, _ media: AudioMediaService) async throws -> MusicDetail? {
        switch page {
        case .appleMusicAlbum(let album): try await albumPage(album, media)
        case .appleMusicPlaylist(let playlist): try await playlistPage(playlist, media)
        case .appleMusicArtist(let artist): try await artistPage(artist, media)
        default: nil
        }
    }

    // MARK: Album

    static func albumPage(_ album: Album, _ media: AudioMediaService) async throws -> MusicDetail {
        let full = try await album.with([.tracks, .artists])
        let tracks = Array(full.tracks ?? [])
        let rows = tracks.enumerated().map { index, track in
            // Compilations name each track's artist. Otherwise the header already does.
            let subtitle = track.artistName == full.artistName ? nil : track.artistName
            let item = MusicTileItem(id: track.id.rawValue, title: track.title, subtitle: subtitle, artwork: track.artwork) {
                Task { await media.playAlbum(full, startingAt: track) }
            }
            return MusicDetail.Track(item: item.with(trackMenu(track, media)), number: track.trackNumber ?? index + 1,
                                     duration: track.duration)
        }
        var actions = AppleMusicTiles.collectionMenu(full, page: nil, openTitle: "", media)
        if let artist = full.artists?.first {
            actions.open = { media.pages.push(.appleMusicArtist(artist)) }
            actions.openTitle = "Show Artist"
            actions.openSystemImage = "music.mic"
        }
        let year = full.releaseDate?.formatted(.dateTime.year())
        let summary = MusicDetail.summary(songCount: tracks.count, duration: tracks.compactMap(\.duration).reduce(0, +))
        return MusicDetail(
            kind: .album, title: full.title, subtitle: full.artistName,
            detail: [year, summary].compactMap { $0 }.joined(separator: ", "),
            header: MusicTileItem(id: full.id.rawValue, title: full.title, subtitle: full.artistName, artwork: full.artwork,
                                  systemImage: "square.stack") { Task { await media.playMusic(full) } },
            tracks: rows, actions: actions
        )
    }

    private static func trackMenu(_ track: Track, _ media: AudioMediaService) -> MusicItemMenu {
        guard case .song(let song) = track else { return MusicItemMenu() }
        return AppleMusicTiles.songMenu(song, media, showsAlbum: false)
    }

    // MARK: Playlist

    static func playlistPage(_ playlist: Playlist, _ media: AudioMediaService) async throws -> MusicDetail {
        let full = try await playlist.with([.entries])
        let entries = Array(full.entries ?? [])
        let rows = entries.map { entry in
            var menu = MusicItemMenu()
            if case .song(let song) = entry.item { menu = AppleMusicTiles.songMenu(song, media) }
            let item = MusicTileItem(id: entry.id.rawValue, title: entry.title, subtitle: entry.artistName, artwork: entry.artwork) {
                Task { await media.playPlaylist(full, startingAt: entry) }
            }
            return MusicDetail.Track(item: item.with(menu), duration: entry.duration)
        }
        let description = full.shortDescription ?? full.standardDescription
        return MusicDetail(
            kind: .playlist, title: full.name, subtitle: full.curatorName,
            detail: description ?? MusicDetail.summary(songCount: entries.count, duration: entries.compactMap(\.duration).reduce(0, +)),
            header: MusicTileItem(id: full.id.rawValue, title: full.name, subtitle: full.curatorName, artwork: full.artwork,
                                  systemImage: "music.note.list") { Task { await media.playMusic(full) } },
            tracks: rows, actions: AppleMusicTiles.collectionMenu(full, page: nil, openTitle: "", media)
        )
    }

    // MARK: Artist

    /// An artist's top songs, albums, singles and similar artists. A library
    /// artist gets the catalog artist of the same name for its top songs, and
    /// keeps the albums in the library.
    static func artistPage(_ artist: Artist, _ media: AudioMediaService) async throws -> MusicDetail {
        let catalogArtist = AppleMusicTiles.isCatalog(artist.id) ? artist : await catalogMatch(for: artist)
        var topSongs: [Song] = []
        var albums: [Album] = []
        var singles: [Album] = []
        var similar: [Artist] = []
        if let catalogArtist, let full = try? await catalogArtist.with([.topSongs, .fullAlbums, .singles, .similarArtists]) {
            topSongs = Array(full.topSongs ?? [])
            albums = Array(full.fullAlbums ?? [])
            singles = Array(full.singles ?? [])
            similar = Array(full.similarArtists ?? [])
        }
        if !AppleMusicTiles.isCatalog(artist.id), let library = try? await artist.with([.albums]) {
            albums = Array(library.albums ?? [])
        }
        if topSongs.isEmpty { topSongs = (try? await librarySongs(by: artist)) ?? [] }
        let recent = RecentMusicItem.appleMusic(artist)
        let rows = topSongs.prefix(10).map { song in
            let item = MusicTileItem(id: song.id.rawValue, title: song.title, subtitle: song.albumTitle, artwork: song.artwork) {
                Task { await media.playSongs(topSongs, startingAt: song, recent: recent) }
            }
            return MusicDetail.Track(item: item.with(AppleMusicTiles.songMenu(song, media)), duration: song.duration)
        }
        var actions = MusicItemMenu()
        actions.play = { Task { await media.playArtist(artist) } }
        actions.shuffle = { Task { await media.playArtist(artist, shuffled: true) } }
        AppleMusicTiles.addQueueActions(to: &actions, items: topSongs, recent: recent, media)
        return MusicDetail(
            kind: .artist, title: artist.name, subtitle: nil, detail: nil,
            header: MusicTileItem(id: artist.id.rawValue, title: artist.name, subtitle: nil,
                                  artwork: artist.artwork ?? catalogArtist?.artwork, systemImage: "music.mic", isRound: true) {
                Task { await media.playArtist(artist) }
            },
            tracksTitle: rows.isEmpty ? nil : "Top Songs", tracks: rows,
            shelves: [
                MusicShelfModel(title: "Albums", items: albums.map { AppleMusicTiles.album($0, media, opensPage: true) }),
                MusicShelfModel(title: "Singles and EPs", items: singles.map { AppleMusicTiles.album($0, media, opensPage: true) }),
                MusicShelfModel(title: "Similar Artists", items: similar.map { AppleMusicTiles.artist($0, media) }),
            ],
            actions: actions
        )
    }

    /// An artist's top songs, for the artist Play button: the catalog's, else the library's.
    static func topSongs(of artist: Artist) async throws -> [Song] {
        let catalogArtist = AppleMusicTiles.isCatalog(artist.id) ? artist : await catalogMatch(for: artist)
        if let catalogArtist, let songs = try? await catalogArtist.with([.topSongs]).topSongs, !songs.isEmpty {
            return Array(songs)
        }
        return try await librarySongs(by: artist)
    }

    /// The catalog artist with the same name as a library artist.
    private static func catalogMatch(for artist: Artist) async -> Artist? {
        var request = MusicCatalogSearchRequest(term: artist.name, types: [Artist.self])
        request.limit = 5
        let found = try? await request.response().artists
        return found?.first { $0.name.caseInsensitiveCompare(artist.name) == .orderedSame }
    }

    private static func librarySongs(by artist: Artist) async throws -> [Song] {
        var request = MusicLibraryRequest<Song>()
        request.filter(matching: \.artists, contains: artist)
        request.limit = 50
        return Array(try await request.response().items)
    }
}
