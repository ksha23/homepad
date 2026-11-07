import Foundation
import HomePadCore
import MusicKit

/// Builds search results from Music Assistant, the Apple Music catalog, or the
/// library and radio when the catalog does not work.
@MainActor
extension SearchResultsModel {
    /// - Parameter tile: Makes a tile for an item. Music Assistant tiles play on the chosen speaker.
    init(musicAssistant results: MASearchResults, query: String, media: AudioMediaService,
         tile: (MAMediaItem) -> MusicTileItem) {
        let best = results.bestMatch(for: query)
        top = best.map(tile)
        topKind = best?.mediaType.singularTitle
        songs = results.tracks.map(tile)
        shelves = [
            MusicShelfModel(title: "Artists", items: results.artists.map(tile)),
            MusicShelfModel(title: "Albums", items: results.albums.map(tile)),
            MusicShelfModel(title: "Playlists", items: results.playlists.map(tile)),
            MusicShelfModel(title: "Radio", items: results.radio.map(tile)),
            MusicShelfModel(title: "Podcasts", items: results.podcasts.map(tile)),
        ]
    }

    init(musicAssistant results: MASearchResults, query: String, media: AudioMediaService) {
        let playing = media.musicAssistant.activePlayer
        self.init(musicAssistant: results, query: query, media: media) { MusicShelves.tile($0, media, playing: playing) }
    }

    /// Spotify's results: the first artist, album or song on top, then songs and shelves.
    init(spotify results: SpotifySearchResults, media: AudioMediaService) {
        let tile = { (item: SpotifyItem) in SpotifyPages.tile(item, media, opensPage: true) }
        let best = results.artists.first.map { (tile($0), "Artist") }
            ?? results.tracks.first.map { (tile($0), "Song") }
            ?? results.albums.first.map { (tile($0), "Album") }
        top = best?.0
        topKind = best?.1
        songs = results.tracks.map(tile)
        shelves = [
            MusicShelfModel(title: "Artists", items: results.artists.map(tile)),
            MusicShelfModel(title: "Albums", items: results.albums.map(tile)),
            MusicShelfModel(title: "Playlists", items: results.playlists.map(tile)),
        ]
    }

    init(thisIPadFor query: String, media: AudioMediaService) {
        if media.demo != nil {
            let demo = MASearchResults(json: (try? JSONValue.parse(Self.demoJSON(query))) ?? .null)
            self.init(musicAssistant: demo, query: query, media: media) { DemoMusicPages.tile($0, media, opensPage: true) }
            return
        }
        self = .empty
        if media.catalog.status.canBrowseCatalog, let response = media.catalog.searchResults {
            self = SearchResultsModel(catalog: response, media: media)
        }
        if let entry = media.mediaLibrary.bestMatch(for: query), top == nil {
            top = MusicTileItem(id: "\(entry.id)", title: entry.title, subtitle: entry.subtitle, libraryArtwork: entry.artwork) {
                Task { await media.perform { try await media.playLibrary(entry) } }
            }
            topKind = "In Your Library"
        }
        shelves.append(MusicShelfModel(title: "Radio Stations", items: media.radioLibrary.searchResults.map { station in
            MusicTileItem(id: station.id, title: station.name, subtitle: station.subtitle, artworkURL: station.artworkURL,
                          systemImage: "dot.radiowaves.left.and.right") {
                Task { await media.perform { try await media.play(station: station) } }
            }
        }))
    }

    /// Albums, playlists and artists open their page, as in the Music app. Songs
    /// and stations play. The Top Result's Play button plays either way.
    private init(catalog response: MusicCatalogSearchResponse, media: AudioMediaService) {
        let songs = Array(response.songs)
        let songTile = { (song: Song) in AppleMusicTiles.song(song, in: songs, media) }
        let artistTile = { (artist: Artist) in AppleMusicTiles.artist(artist, media) }
        let albumTile = { (album: Album) in AppleMusicTiles.album(album, media, opensPage: true) }
        let playlistTile = { (playlist: Playlist) in AppleMusicTiles.playlist(playlist, media, opensPage: true) }
        let stationTile = { (station: Station) in AppleMusicTiles.station(station, media) }
        self.songs = songs.map(songTile)
        // Apple's own best match, as in Apple Music, so an artist's name finds
        // the artist. The first album stood in for every search before.
        let best = response.topResults.lazy.compactMap { result -> (MusicTileItem, String)? in
            switch result {
            case .artist(let artist): (artistTile(artist), "Artist")
            case .album(let album): (albumTile(album), "Album")
            case .song(let song): (songTile(song), "Song")
            case .playlist(let playlist): (playlistTile(playlist), "Playlist")
            case .station(let station): (stationTile(station), "Station")
            default: nil
            }
        }.first
        if let best {
            (top, topKind) = best
        } else if let album = response.albums.first {
            top = albumTile(album)
            topKind = "Album"
        }
        shelves = [
            MusicShelfModel(title: "Artists", items: response.artists.map(artistTile)),
            MusicShelfModel(title: "Albums", items: response.albums.map(albumTile)),
            MusicShelfModel(title: "Playlists", items: response.playlists.map(playlistTile)),
            MusicShelfModel(title: "Stations", items: response.stations.map(stationTile)),
        ]
    }

    /// The demo catalog's answer, through the same decoder as Music Assistant's.
    private static func demoJSON(_ query: String) -> String {
        let needle = query.lowercased()
        func list(_ type: MAMediaItem.MediaType) -> JSONValue {
            .array(DemoMusicCatalog.items(of: type).filter {
                $0.name.lowercased().contains(needle) || $0.artists.contains { $0.lowercased().contains(needle) }
            }.map(\.json))
        }
        let object: JSONValue = ["artists": list(.artist), "albums": list(.album), "tracks": list(.track),
                                 "playlists": list(.playlist), "radio": list(.radio)]
        return object.jsonString()
    }
}
