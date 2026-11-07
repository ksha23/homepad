import Foundation

/// An internet radio stream HomePad can play with `AVPlayer`.
public struct RadioStation: Identifiable, Codable, Hashable, Sendable {
    /// Where a station came from.
    public enum Origin: String, Codable, Sendable {
        case curated        // built into HomePad
        case radioBrowser   // found through the Radio Browser directory
        case custom         // added by URL
    }

    /// Stable ID such as `soma:groovesalad`, `rb:<stationuuid>` or `custom:<uuid>`.
    public var id: String
    public var name: String
    public var streamURL: URL
    public var artworkURL: URL?
    public var homepageURL: URL?
    /// Short genre words, for example ["ambient", "chillout"].
    public var tags: [String]
    public var countryCode: String?
    public var codec: String?
    /// Kilobits per second when known.
    public var bitrate: Int?
    public var origin: Origin

    public init(
        id: String, name: String, streamURL: URL, artworkURL: URL? = nil, homepageURL: URL? = nil,
        tags: [String] = [], countryCode: String? = nil, codec: String? = nil, bitrate: Int? = nil,
        origin: Origin
    ) {
        self.id = id
        self.name = name
        self.streamURL = streamURL
        self.artworkURL = artworkURL
        self.homepageURL = homepageURL
        self.tags = tags
        self.countryCode = countryCode
        self.codec = codec
        self.bitrate = bitrate
        self.origin = origin
    }

    /// One line such as "Ambient, Chillout" for lists.
    public var subtitle: String {
        let genre = tags.prefix(2).map(\.capitalized).joined(separator: ", ")
        return genre.isEmpty ? (countryCode ?? "Internet radio") : genre
    }

    /// A station for a stream URL the person typed in.
    public static func custom(name: String, url: URL) -> RadioStation {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return RadioStation(
            id: "custom:\(UUID().uuidString)", name: trimmed.isEmpty ? (url.host() ?? "Stream") : trimmed,
            streamURL: url, origin: .custom
        )
    }
}
