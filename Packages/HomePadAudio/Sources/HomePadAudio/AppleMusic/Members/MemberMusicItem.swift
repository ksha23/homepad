import Foundation

/// A song, album, playlist, artist or station from a household member's own
/// Apple Music, read with their token. Kept in their encrypted cache.
///
/// This iPad plays through its own Apple Music account, which cannot see the
/// member's library. So an item plays here by its catalog ID: an album or
/// song the person added from Apple Music has one, and a song they uploaded
/// themselves does not.
struct MemberMusicItem: Codable, Hashable, Identifiable, Sendable {
    enum Kind: String, Codable, Sendable {
        case song, album, playlist, artist, station
    }

    /// The item's ID where it lives: the person's library ("i.", "l.", "p.", "r.") or the catalog.
    var id: String
    var kind: Kind
    var title: String
    /// The artist of a song or album, the curator of a playlist.
    var subtitle: String?
    /// Apple's artwork address with `{w}` and `{h}` for the size.
    var artworkTemplate: String?
    /// The catalog ID this iPad plays it by. Nil when the catalog does not have it.
    var catalogID: String?
    /// True for an item in the person's library, false for a catalog item
    /// (recently played and recommendations are mostly catalog items).
    var isLibrary: Bool
    var duration: TimeInterval?
    var trackNumber: Int?
    /// When it was added to the library, as the API gives it (ISO 8601), for Recently Added.
    var dateAdded: String?

    /// Why this iPad cannot play it, or nil when it can.
    ///
    /// - Songs, albums and artists need a catalog match. Uploads have none.
    /// - The person's own playlists always open, and play the songs in them that have one.
    /// - A personal station ("ra.u-") is made for its owner's account, so it plays only there.
    var unavailableReason: String? {
        switch kind {
        case .playlist:
            return nil
        case .station:
            if id.hasPrefix("ra.u-") || catalogID?.hasPrefix("ra.u-") == true { return "Only on its owner's account" }
            return catalogID == nil ? "Not in Apple Music" : nil
        case .song, .album, .artist:
            return catalogID == nil ? "Not in Apple Music" : nil
        }
    }

    var isPlayable: Bool { unavailableReason == nil }

    /// The artwork at a square size, in pixels.
    func artworkURL(side: Int = 600) -> URL? {
        guard let artworkTemplate else { return nil }
        return URL(string: artworkTemplate.replacingOccurrences(of: "{w}", with: "\(side)").replacingOccurrences(of: "{h}", with: "\(side)"))
    }

    /// The date it was added, for sorting. Library albums give a full date or a year.
    var addedDate: Date? {
        guard let dateAdded else { return nil }
        if let full = try? Date(dateAdded, strategy: .iso8601) { return full }
        return try? Date(dateAdded, strategy: Date.ISO8601FormatStyle().year().month().day())
    }
}

extension MemberMusicItem {
    /// Reads one API resource. Nil for kinds HomePad does not play here, such
    /// as music videos, and for resources without a name.
    init?(_ resource: APIResource) {
        guard let attributes = resource.attributes, let name = attributes.name, !name.isEmpty else { return nil }
        let match = resource.relationships?.catalog?.data?.first
        let kind: Kind
        let catalogID: String?
        let isLibrary = resource.type.hasPrefix("library-")
        switch resource.type {
        case "library-songs":
            kind = .song
            catalogID = match?.id ?? attributes.playParams?.catalogId
        case "library-albums":
            kind = .album
            catalogID = match?.id
        case "library-playlists":
            kind = .playlist
            catalogID = match?.id ?? attributes.playParams?.globalId
        case "library-artists":
            kind = .artist
            catalogID = match?.id
        case "songs": (kind, catalogID) = (.song, resource.id)
        case "albums": (kind, catalogID) = (.album, resource.id)
        case "playlists": (kind, catalogID) = (.playlist, resource.id)
        case "artists": (kind, catalogID) = (.artist, resource.id)
        case "stations": (kind, catalogID) = (.station, resource.id)
        default: return nil
        }
        let subtitle: String? = switch kind {
        case .song, .album: attributes.artistName
        case .playlist: attributes.curatorName
        case .artist, .station: nil
        }
        self.init(
            id: resource.id, kind: kind, title: name, subtitle: subtitle,
            artworkTemplate: attributes.artwork?.url ?? match?.attributes?.artwork?.url,
            catalogID: catalogID, isLibrary: isLibrary,
            duration: attributes.durationInMillis.map { TimeInterval($0) / 1000 },
            trackNumber: attributes.trackNumber, dateAdded: attributes.dateAdded
        )
    }

    /// Reads a list, skipping what HomePad cannot show.
    static func list(_ resources: [APIResource]) -> [MemberMusicItem] {
        resources.compactMap(MemberMusicItem.init)
    }
}

/// A titled group of a member's recommendations, such as "Made for You".
struct MemberMusicShelf: Codable, Equatable, Identifiable, Sendable {
    var title: String
    var items: [MemberMusicItem]
    var id: String { title }

    /// Reads one `personal-recommendation` resource. Nil when it has nothing HomePad can show.
    init?(_ resource: APIResource) {
        let items = MemberMusicItem.list(resource.relationships?.contents?.data ?? [])
        guard !items.isEmpty else { return nil }
        self.title = resource.attributes?.title?.stringForDisplay ?? "Made for You"
        self.items = items
    }

    init(title: String, items: [MemberMusicItem]) {
        self.title = title
        self.items = items
    }
}
