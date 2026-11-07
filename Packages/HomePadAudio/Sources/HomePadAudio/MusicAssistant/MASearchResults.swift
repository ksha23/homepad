import Foundation
import HomePadCore

/// The response of `music_assistant.search`: one list per media type, each
/// holding up to `limit` items (Home Assistant's `SEARCH_RESULT_SCHEMA`).
struct MASearchResults: Equatable, Sendable {
    var artists: [MAMediaItem] = []
    var albums: [MAMediaItem] = []
    var tracks: [MAMediaItem] = []
    var playlists: [MAMediaItem] = []
    var radio: [MAMediaItem] = []
    var audiobooks: [MAMediaItem] = []
    var podcasts: [MAMediaItem] = []

    init(artists: [MAMediaItem] = [], albums: [MAMediaItem] = [], tracks: [MAMediaItem] = [],
         playlists: [MAMediaItem] = [], radio: [MAMediaItem] = [], audiobooks: [MAMediaItem] = [],
         podcasts: [MAMediaItem] = []) {
        self.artists = artists
        self.albums = albums
        self.tracks = tracks
        self.playlists = playlists
        self.radio = radio
        self.audiobooks = audiobooks
        self.podcasts = podcasts
    }

    init(json: JSONValue) {
        self.init(
            artists: MAMediaItem.list(json["artists"]), albums: MAMediaItem.list(json["albums"]),
            tracks: MAMediaItem.list(json["tracks"]), playlists: MAMediaItem.list(json["playlists"]),
            radio: MAMediaItem.list(json["radio"]), audiobooks: MAMediaItem.list(json["audiobooks"]),
            podcasts: MAMediaItem.list(json["podcasts"])
        )
    }

    var isEmpty: Bool { all.isEmpty }

    /// Every item, in the order the shelves show them.
    var all: [MAMediaItem] { artists + albums + tracks + playlists + radio + podcasts + audiobooks }

    /// Items of one type.
    func items(of type: MAMediaItem.MediaType) -> [MAMediaItem] {
        switch type {
        case .artist: artists
        case .album: albums
        case .track: tracks
        case .playlist: playlists
        case .radio: radio
        case .audiobook: audiobooks
        case .podcast: podcasts
        case .folder, .unknown: []
        }
    }

    /// The single best thing to play for a request such as "Taylor Swift" or "chill playlist".
    /// - An explicit kind word ("playlist", "album", "radio" or "station") picks that kind.
    /// - An artist or album whose name matches the request exactly wins next.
    /// - Then the first track, playlist, album, artist and station, in that order.
    func bestMatch(for query: String, preferring type: MAMediaItem.MediaType? = nil) -> MAMediaItem? {
        if let type, let first = items(of: type).first { return first }
        let lowered = query.lowercased()
        if lowered.contains("playlist"), let first = playlists.first { return first }
        if lowered.contains("album"), let first = albums.first { return first }
        if lowered.contains("radio") || lowered.contains("station"), let first = radio.first { return first }
        let needle = Self.normalized(query)
        if let artist = artists.first(where: { Self.normalized($0.name) == needle }) { return artist }
        if let album = albums.first(where: { Self.normalized($0.name) == needle }) { return album }
        if let playlist = playlists.first(where: { Self.normalized($0.name) == needle }) { return playlist }
        return tracks.first ?? playlists.first ?? albums.first ?? artists.first ?? radio.first ?? podcasts.first
    }

    private static func normalized(_ text: String) -> String {
        text.lowercased().filter { $0.isLetter || $0.isNumber }
    }
}
