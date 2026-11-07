import Foundation
import MusicKit

/// One person's music on this iPad: where their queue was, the songs that
/// follow, shuffle and repeat, and what they played lately. Saved per owner
/// (`MusicQueueOwner.stateKey`), so each member's queue and place come back
/// when HomePad recognizes them, and guests share the household's.
struct MemberMusicState: Codable, Equatable, Sendable {
    /// The saved song, its queue's source and the moment.
    var resume: MusicResumePoint?
    /// The songs after the saved one, so Up Next shows them before playback starts again.
    var upNext: [SavedQueueItem] = []
    var shuffle = false
    var repeatMode: MusicRepeatMode = .off
    /// The album, playlist or station the queue started from, for "Playing from".
    var originTitle: String?
    /// Newest first.
    var recents: [RecentMusicItem] = []

    /// How many upcoming songs are kept for Up Next.
    static let upNextLimit = 50
    /// How many recently played items are kept.
    static let recentsLimit = 24

    init() {}

    /// Reads every field when present, so a state saved before a field existed still loads.
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        resume = try container.decodeIfPresent(MusicResumePoint.self, forKey: .resume)
        upNext = try container.decodeIfPresent([SavedQueueItem].self, forKey: .upNext) ?? []
        shuffle = try container.decodeIfPresent(Bool.self, forKey: .shuffle) ?? false
        repeatMode = try container.decodeIfPresent(MusicRepeatMode.self, forKey: .repeatMode) ?? .off
        originTitle = try container.decodeIfPresent(String.self, forKey: .originTitle)
        recents = try container.decodeIfPresent([RecentMusicItem].self, forKey: .recents) ?? []
    }

    /// Puts `item` first in Recently Played, without a second copy and within the limit.
    mutating func noteRecent(_ item: RecentMusicItem) {
        recents.removeAll { $0.id == item.id }
        recents.insert(item, at: 0)
        if recents.count > Self.recentsLimit { recents.removeLast(recents.count - Self.recentsLimit) }
    }

    /// True when there is nothing worth keeping.
    var isEmpty: Bool { resume == nil && upNext.isEmpty && recents.isEmpty && !shuffle && repeatMode == .off }
}

/// One upcoming song in a saved queue, with what Up Next shows for it.
struct SavedQueueItem: Codable, Equatable, Identifiable, Sendable {
    /// The MusicKit song ID, or another source's ID.
    var id: String
    var title: String
    var subtitle: String?
    var artwork: Artwork?
    var artworkURL: URL?

    init(id: String, title: String, subtitle: String? = nil, artwork: Artwork? = nil, artworkURL: URL? = nil) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.artwork = artwork
        self.artworkURL = artworkURL
    }

    init(_ item: QueueItem) {
        self.init(id: item.songID ?? item.id, title: item.title, subtitle: item.subtitle,
                  artwork: item.artwork, artworkURL: item.artworkURL)
    }

    /// The row Up Next shows.
    var queueItem: QueueItem {
        QueueItem(id: "saved-\(id)", title: title, subtitle: subtitle, artworkURL: artworkURL, artwork: artwork, songID: id)
    }
}

/// Repeat, as the Music app offers it: off, the whole queue, or one song.
enum MusicRepeatMode: String, Codable, CaseIterable, Sendable {
    case off, all, one

    /// The next mode when the repeat button is tapped: off, all, one, off.
    var next: MusicRepeatMode {
        switch self {
        case .off: .all
        case .all: .one
        case .one: .off
        }
    }

    var systemImage: String { self == .one ? "repeat.1" : "repeat" }

    /// What VoiceOver reads for the repeat button.
    var label: String {
        switch self {
        case .off: "Repeat Off"
        case .all: "Repeat All"
        case .one: "Repeat One"
        }
    }
}

/// Something a person played on HomePad, for their Recently Played shelf.
struct RecentMusicItem: Codable, Equatable, Identifiable, Sendable {
    enum Kind: String, Codable, Sendable {
        case album, playlist, station, song, artist
    }

    /// Where the item comes from, so a tap plays it from the same place.
    enum Source: String, Codable, Sendable {
        case appleMusic, demo, spotify
        /// A member's own playlist, which only their token can read (`MemberMusicPlayback`).
        case memberLibrary
    }

    var source: Source
    var kind: Kind
    /// The item's ID in its source: a MusicKit ID, a demo name or a Spotify URI.
    var itemID: String
    var title: String
    var subtitle: String?
    var artwork: Artwork?
    var artworkURL: URL?
    var playedAt: Date

    var id: String { "\(source.rawValue):\(kind.rawValue):\(itemID)" }

    init(source: Source, kind: Kind, itemID: String, title: String, subtitle: String? = nil,
         artwork: Artwork? = nil, artworkURL: URL? = nil, playedAt: Date = Date()) {
        self.source = source
        self.kind = kind
        self.itemID = itemID
        self.title = title
        self.subtitle = subtitle
        self.artwork = artwork
        self.artworkURL = artworkURL
        self.playedAt = playedAt
    }

    var systemImage: String {
        switch kind {
        case .album: "square.stack"
        case .playlist: "music.note.list"
        case .station: "dot.radiowaves.left.and.right"
        case .song: "music.note"
        case .artist: "music.mic"
        }
    }
}
