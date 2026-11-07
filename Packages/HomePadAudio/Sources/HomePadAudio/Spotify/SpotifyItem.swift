import Foundation
import HomePadCore

/// A Spotify track, album, playlist or artist as the Web API describes it
/// (https://developer.spotify.com/documentation/web-api). Read with
/// `init(json:)` from search, library, player and page responses.
struct SpotifyItem: Hashable, Identifiable, Sendable {
    enum Kind: String, Sendable {
        case track, album, playlist, artist, episode
    }

    var kind: Kind
    /// Spotify's ID, such as "4aawyAB9vmqN3uQ7FjRGTy".
    var id: String
    /// "spotify:album:4aawyAB9vmqN3uQ7FjRGTy", for playing and queueing.
    var uri: String
    var name: String
    /// Artists for tracks and albums, the owner for playlists.
    var subtitle: String?
    var imageURL: URL?
    var duration: TimeInterval?
    /// The album a track is on, for Now Playing.
    var albumName: String?
    /// The album's own item, for opening a track's album.
    var albumID: String?
    /// The item on open.spotify.com, for "Open Spotify".
    var webURL: URL?

    /// Reads one object. Nil without an ID, URI or name (Spotify returns null
    /// entries for items that are no longer available).
    init?(json: JSONValue?, kind fallback: Kind? = nil) {
        guard let json, let id = json["id"]?.stringValue, let uri = json["uri"]?.stringValue,
              let name = json["name"]?.stringValue,
              let kind = Kind(rawValue: json["type"]?.stringValue ?? "") ?? fallback else { return nil }
        self.kind = kind
        self.id = id
        self.uri = uri
        self.name = name
        let artists = (json["artists"]?.arrayValue ?? []).compactMap { $0["name"]?.stringValue }
        switch kind {
        case .playlist: subtitle = json["owner"]?["display_name"]?.stringValue
        case .episode: subtitle = json["show"]?["name"]?.stringValue
        default: subtitle = artists.isEmpty ? nil : artists.formatted(.list(type: .and))
        }
        let images = json["images"]?.arrayValue ?? json["album"]?["images"]?.arrayValue ?? []
        imageURL = Self.bestImage(images)
        duration = json["duration_ms"]?.doubleValue.map { $0 / 1000 }
        albumName = json["album"]?["name"]?.stringValue
        albumID = json["album"]?["id"]?.stringValue
        webURL = json["external_urls"]?["spotify"]?.stringValue.flatMap(URL.init(string:))
    }

    init(kind: Kind, id: String, name: String, subtitle: String? = nil, imageURL: URL? = nil) {
        self.kind = kind
        self.id = id
        uri = "spotify:\(kind.rawValue):\(id)"
        self.name = name
        self.subtitle = subtitle
        self.imageURL = imageURL
    }

    /// The largest image up to about 640 pixels, which Spotify lists first.
    static func bestImage(_ images: [JSONValue]) -> URL? {
        let sized = images.compactMap { image -> (URL, Int)? in
            guard let url = image["url"]?.stringValue.flatMap(URL.init(string:)) else { return nil }
            return (url, image["width"]?.intValue ?? 0)
        }
        let fitting = sized.filter { $0.1 <= 700 }.max { $0.1 < $1.1 }
        return (fitting ?? sized.first)?.0
    }

    /// Reads a list, skipping nulls and unreadable entries. `field` unwraps
    /// wrappers such as saved albums (`album`) and playlist items (`item` or `track`).
    static func list(_ json: JSONValue?, unwrapping fields: [String] = [], kind: Kind? = nil) -> [SpotifyItem] {
        (json?.arrayValue ?? []).compactMap { entry in
            let inner = fields.lazy.compactMap { entry[$0] }.first { $0.objectValue != nil } ?? entry
            return SpotifyItem(json: inner, kind: kind)
        }
    }

    var systemImage: String {
        switch kind {
        case .track: "music.note"
        case .album: "square.stack"
        case .playlist: "music.note.list"
        case .artist: "music.mic"
        case .episode: "mic.fill"
        }
    }
}

extension SpotifyItem {
    /// The page a Recently Played entry from Spotify stands for.
    init?(recent: RecentMusicItem) {
        let parts = recent.itemID.split(separator: ":")
        guard recent.source == .spotify, parts.count == 3, let kind = Kind(rawValue: String(parts[1])),
              [.album, .playlist, .artist].contains(kind) else { return nil }
        self.init(kind: kind, id: String(parts[2]), name: recent.title, subtitle: recent.subtitle, imageURL: recent.artworkURL)
    }

    /// A Recently Played entry for this item.
    var recent: RecentMusicItem {
        let kind: RecentMusicItem.Kind = switch self.kind {
        case .album: .album
        case .playlist: .playlist
        case .artist: .artist
        case .track, .episode: .song
        }
        return RecentMusicItem(source: .spotify, kind: kind, itemID: uri, title: name, subtitle: subtitle, artworkURL: imageURL)
    }
}
