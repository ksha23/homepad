import Foundation
import HomePadCore

/// Made-up music for simulator screenshots: artists, albums, songs, playlists and
/// stations from a few providers, as Music Assistant would report them. Artwork is
/// drawn by `GeneratedArtwork`, so nothing is fetched.
enum DemoMusicCatalog {
    struct Track: Equatable {
        let title: String
        let artist: String
        let album: String
        let duration: TimeInterval
    }

    static let tracks: [Track] = [
        Track(title: "Golden Hour Drive", artist: "Neon Avenue", album: "Night Signals", duration: 177),
        Track(title: "Echoes in Blue", artist: "Neon Avenue", album: "Night Signals", duration: 198),
        Track(title: "Paper Planes at Dusk", artist: "The Quiet Coast", album: "Low Tide", duration: 204),
        Track(title: "Undertow", artist: "The Quiet Coast", album: "Low Tide", duration: 221),
        Track(title: "Slow Morning", artist: "Lumen", album: "Kitchen Radio", duration: 189),
        Track(title: "Coffee and Rain", artist: "Lumen", album: "Kitchen Radio", duration: 176),
        Track(title: "Far From the City", artist: "Arden Lane", album: "Field Notes", duration: 231),
        Track(title: "Velvet Sky", artist: "Velvet Hours", album: "Slow Bloom", duration: 245),
        Track(title: "Lanterns", artist: "Paper Lanterns", album: "Lantern Light", duration: 212),
        Track(title: "Static Hearts", artist: "Mara Solis", album: "Golden Static", duration: 193),
        Track(title: "Open Road", artist: "Northbound", album: "Open Road", duration: 238),
        Track(title: "Blue Hour", artist: "Lumen", album: "Blue Hour Sessions", duration: 254),
        Track(title: "Saltwater", artist: "The Quiet Coast", album: "Saltwater", duration: 209),
        Track(title: "Midnight Garden", artist: "Velvet Hours", album: "Slow Bloom", duration: 226),
    ]

    static let artistNames = [
        "Neon Avenue", "The Quiet Coast", "Lumen", "Arden Lane", "Velvet Hours", "Paper Lanterns", "Mara Solis", "Northbound",
    ]

    static var artists: [MAMediaItem] {
        artistNames.enumerated().map { index, name in
            MAMediaItem(mediaType: .artist, uri: "apple_music://artist/\(200 + index)", name: name, isFavorite: index < 3)
        }
    }

    static var albums: [MAMediaItem] {
        var seen = Set<String>()
        return tracks.enumerated().compactMap { index, track in
            guard seen.insert(track.album).inserted else { return nil }
            return MAMediaItem(mediaType: .album, uri: "apple_music://album/\(300 + index)", name: track.album,
                               isFavorite: index % 3 == 0, artists: [track.artist])
        }
    }

    static var trackItems: [MAMediaItem] {
        tracks.enumerated().map { index, track in
            MAMediaItem(mediaType: .track, uri: "apple_music://track/\(100 + index)", name: track.title,
                        isFavorite: index % 2 == 0, artists: [track.artist], albumName: track.album)
        }
    }

    static let playlists: [MAMediaItem] = [
        MAMediaItem(mediaType: .playlist, uri: "apple_music://playlist/pl.dinner", name: "Dinner Party", isFavorite: true),
        MAMediaItem(mediaType: .playlist, uri: "apple_music://playlist/pl.sunday", name: "Sunday Morning", isFavorite: true),
        MAMediaItem(mediaType: .playlist, uri: "spotify://playlist/focusflow", name: "Focus Flow"),
        MAMediaItem(mediaType: .playlist, uri: "apple_music://playlist/pl.disco", name: "Kitchen Disco"),
        MAMediaItem(mediaType: .playlist, uri: "spotify://playlist/latenightjazz", name: "Late Night Jazz"),
        MAMediaItem(mediaType: .playlist, uri: "apple_music://playlist/pl.roadtrip", name: "Road Trip"),
        MAMediaItem(mediaType: .playlist, uri: "library://playlist/7", name: "Chill Mix"),
        MAMediaItem(mediaType: .playlist, uri: "apple_music://playlist/pl.rain", name: "Rainy Day"),
    ]

    static let radio: [MAMediaItem] = [
        MAMediaItem(mediaType: .radio, uri: "tunein://radio/s1", name: "Morning Jazz Radio", isFavorite: true),
        MAMediaItem(mediaType: .radio, uri: "radiobrowser://radio/lofi", name: "Lo-Fi Beats"),
        MAMediaItem(mediaType: .radio, uri: "tunein://radio/s2", name: "Indie Mix Radio"),
        MAMediaItem(mediaType: .radio, uri: "radiobrowser://radio/classical", name: "Classical Calm"),
    ]

    /// Every item of one type, the way `get_library` would list it.
    static func items(of type: MAMediaItem.MediaType) -> [MAMediaItem] {
        switch type {
        case .artist: artists
        case .album: albums
        case .track: trackItems
        case .playlist: playlists
        case .radio: radio
        default: []
        }
    }

    /// The songs an album, artist, playlist or song name plays, for the iPad's demo queue.
    static func tracks(matching text: String) -> [Track] {
        let items = [MAMediaItem.MediaType.album, .artist, .playlist, .track].flatMap(items(of:))
        if let item = items.first(where: { $0.name == text }) {
            let songs = queue(for: item)
            if !songs.isEmpty { return songs }
        }
        return tracks
    }

    /// What Play Next and Play Later add: one song for a song's name, else
    /// the album's, artist's or playlist's songs.
    static func tracksToQueue(_ text: String) -> [Track] {
        let isAlbumOrArtist = [MAMediaItem.MediaType.album, .artist, .playlist].flatMap(items(of:)).contains { $0.name == text }
        if !isAlbumOrArtist, let song = tracks.first(where: { $0.title == text }) { return [song] }
        return tracks(matching: text)
    }

    /// The songs an item plays, for the demo queue.
    static func queue(for item: MAMediaItem) -> [Track] {
        switch item.mediaType {
        case .track: tracks.filter { $0.title == item.name } + tracks.filter { $0.title != item.name }.prefix(6)
        case .album: tracks.filter { $0.album == item.name }
        case .artist: tracks.filter { $0.artist == item.name }
        case .playlist:
            Array(tracks.rotated(by: item.name.unicodeScalars.reduce(0) { $0 + Int($1.value) }).prefix(8))
        default: []
        }
    }
}

private extension Array {
    func rotated(by offset: Int) -> [Element] {
        guard !isEmpty else { return self }
        let shift = offset % count
        return Array(self[shift...] + self[..<shift])
    }
}
