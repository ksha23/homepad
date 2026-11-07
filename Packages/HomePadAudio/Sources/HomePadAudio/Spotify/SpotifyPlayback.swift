import Foundation
import HomePadCore

/// What Spotify plays and where, from `GET /me/player`
/// (https://developer.spotify.com/documentation/web-api/reference/get-information-about-the-users-current-playback).
struct SpotifyPlayback: Equatable, Sendable {
    var item: SpotifyItem?
    var device: SpotifyDevice?
    var isPlaying: Bool
    var progress: TimeInterval
    var isShuffled: Bool
    /// "off", "context" or "track".
    var repeatState: String
    /// What the queue plays from, such as "spotify:playlist:…".
    var contextURI: String?
    /// When `progress` was read, so the position moves on between polls.
    var readAt: Date

    /// Nil for an empty answer (204, nothing playing anywhere).
    init?(json: JSONValue, readAt: Date = Date()) {
        guard json.objectValue != nil else { return nil }
        item = SpotifyItem(json: json["item"])
        device = SpotifyDevice(json: json["device"])
        isPlaying = json["is_playing"]?.boolValue ?? false
        progress = (json["progress_ms"]?.doubleValue ?? 0) / 1000
        isShuffled = json["shuffle_state"]?.boolValue ?? false
        repeatState = json["repeat_state"]?.stringValue ?? "off"
        contextURI = json["context"]?["uri"]?.stringValue
        self.readAt = readAt
    }

    /// The position now, moved on from the last reading while playing.
    func elapsed(at now: Date = Date()) -> TimeInterval {
        guard isPlaying else { return progress }
        let moved = progress + now.timeIntervalSince(readAt)
        return item?.duration.map { min(moved, $0) } ?? moved
    }

    var repeatMode: MusicRepeatMode {
        switch repeatState {
        case "track": .one
        case "context": .all
        default: .off
        }
    }

    static func repeatState(for mode: MusicRepeatMode) -> String {
        switch mode {
        case .off: "off"
        case .all: "context"
        case .one: "track"
        }
    }

    /// Now Playing, for every surface.
    func nowPlaying(at now: Date = Date()) -> NowPlaying? {
        guard let item else { return nil }
        return NowPlaying(title: item.name, artist: item.subtitle, album: item.albumName, artworkURL: item.imageURL,
                          duration: item.duration, elapsed: elapsed(at: now), isPlaying: isPlaying,
                          source: .system, outputName: device?.name)
    }
}

/// A Spotify Connect device: a speaker, a phone, a computer, or the Spotify app on this iPad
/// (https://developer.spotify.com/documentation/web-api/reference/get-a-users-available-devices).
struct SpotifyDevice: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    /// "Computer", "Smartphone", "Speaker", "Tablet" and so on.
    let type: String
    let isActive: Bool
    /// Restricted devices take no commands from the Web API.
    let isRestricted: Bool
    let volume: Double?

    init?(json: JSONValue?) {
        guard let json, let id = json["id"]?.stringValue, let name = json["name"]?.stringValue else { return nil }
        self.id = id
        self.name = name
        type = json["type"]?.stringValue ?? "Speaker"
        isActive = json["is_active"]?.boolValue ?? false
        isRestricted = json["is_restricted"]?.boolValue ?? false
        volume = json["supports_volume"]?.boolValue == false ? nil : json["volume_percent"]?.doubleValue.map { $0 / 100 }
    }

    static func list(_ json: JSONValue) -> [SpotifyDevice] {
        (json["devices"]?.arrayValue ?? []).compactMap(SpotifyDevice.init(json:))
    }

    var systemImage: String {
        switch type.lowercased() {
        case "computer": "laptopcomputer"
        case "smartphone": "iphone"
        case "tablet": "ipad.landscape"
        case "tv": "tv"
        case "castvideo", "castaudio": "tv.and.hifispeaker.fill"
        case "automobile": "car.fill"
        default: "hifispeaker.fill"
        }
    }
}
