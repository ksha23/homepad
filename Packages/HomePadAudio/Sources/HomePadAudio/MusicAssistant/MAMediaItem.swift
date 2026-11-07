import Foundation
import HomePadCore

/// One item in a Music Assistant action response: `music_assistant.search`,
/// `music_assistant.get_library` and the `media_item` of `music_assistant.get_queue`.
/// The fields follow Home Assistant's `MEDIA_ITEM_SCHEMA`: `media_type`, `uri`,
/// `name`, `version`, `image`, and optionally `favorite`, `explicit`, `artists`
/// and `album`.
struct MAMediaItem: Identifiable, Hashable, Sendable {
    /// Music Assistant's media types, as the integration's `media_type` field spells them.
    enum MediaType: String, Sendable, CaseIterable {
        case artist, album, track, playlist, radio, audiobook, podcast, folder
        case unknown

        /// Plural shelf title, for example "Playlists".
        var pluralTitle: String {
            switch self {
            case .artist: "Artists"
            case .album: "Albums"
            case .track: "Songs"
            case .playlist: "Playlists"
            case .radio: "Radio"
            case .audiobook: "Audiobooks"
            case .podcast: "Podcasts"
            case .folder: "Folders"
            case .unknown: "Other"
            }
        }

        /// One word for a subtitle, for example "Album".
        var singularTitle: String {
            switch self {
            case .track: "Song"
            case .radio: "Station"
            default: String(pluralTitle.dropLast())
            }
        }

        var systemImage: String {
            switch self {
            case .artist: "music.mic"
            case .album: "square.stack"
            case .track: "music.note"
            case .playlist: "music.note.list"
            case .radio: "dot.radiowaves.left.and.right"
            case .audiobook: "book.fill"
            case .podcast: "mic.fill"
            case .folder, .unknown: "folder.fill"
            }
        }
    }

    var mediaType: MediaType
    /// Music Assistant's URI, such as `apple_music://track/1645937262`. Pass it to `play_media`.
    var uri: String
    var name: String
    /// A version such as "Remastered 2011". Often empty.
    var version: String
    var imageURL: URL?
    var isFavorite: Bool
    var isExplicit: Bool
    /// Artist names, for tracks and albums.
    var artists: [String]
    var albumName: String?

    var id: String { uri }

    init(mediaType: MediaType, uri: String, name: String, version: String = "", imageURL: URL? = nil,
         isFavorite: Bool = false, isExplicit: Bool = false, artists: [String] = [], albumName: String? = nil) {
        self.mediaType = mediaType
        self.uri = uri
        self.name = name
        self.version = version
        self.imageURL = imageURL
        self.isFavorite = isFavorite
        self.isExplicit = isExplicit
        self.artists = artists
        self.albumName = albumName
    }

    /// Reads one item. Nil when `uri` or `name` is missing.
    init?(json: JSONValue) {
        guard let uri = json["uri"]?.stringValue, let name = json["name"]?.stringValue else { return nil }
        self.init(
            mediaType: MediaType(rawValue: json["media_type"]?.stringValue ?? "") ?? .unknown,
            uri: uri,
            name: name,
            version: json["version"]?.stringValue ?? "",
            imageURL: json["image"]?.stringValue.flatMap(URL.init(string:)),
            isFavorite: json["favorite"]?.boolValue ?? false,
            isExplicit: json["explicit"]?.boolValue ?? false,
            artists: (json["artists"]?.arrayValue ?? []).compactMap { $0["name"]?.stringValue },
            albumName: json["album"]?["name"]?.stringValue
        )
    }

    /// Reads a list, skipping malformed entries.
    static func list(_ json: JSONValue?) -> [MAMediaItem] {
        (json?.arrayValue ?? []).compactMap(MAMediaItem.init(json:))
    }

    /// The name with its version, for example "Abbey Road (Remastered 2019)".
    var displayName: String {
        version.isEmpty ? name : "\(name) (\(version))"
    }

    /// The line under the title: artists for songs and albums, otherwise the kind.
    var subtitle: String {
        let artistLine = artists.formatted(.list(type: .and))
        switch mediaType {
        case .track, .album: return artistLine.isEmpty ? mediaType.singularTitle : artistLine
        default: return mediaType.singularTitle
        }
    }

    /// The music provider part of the URI, for example `apple_music`, `spotify` or `library`.
    var provider: String? {
        guard let range = uri.range(of: "://") else { return nil }
        return String(uri[..<range.lowerBound])
    }

    /// A friendly provider name for a small label, when Music Assistant reports one HomePad knows.
    var providerName: String? {
        switch provider {
        case "apple_music": "Apple Music"
        case "spotify": "Spotify"
        case "tunein": "TuneIn"
        case "radiobrowser": "Radio Browser"
        case "library": "Library"
        case "filesystem_local", "filesystem_smb": "Files"
        default: nil
        }
    }
}
