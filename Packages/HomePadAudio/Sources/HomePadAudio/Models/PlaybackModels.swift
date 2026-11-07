import Foundation
import MusicKit

/// One upcoming item in a queue, for Up Next.
struct QueueItem: Identifiable, Hashable, Sendable {
    /// The queue entry's own ID, unique even when a song is queued twice.
    let id: String
    let title: String
    let subtitle: String?
    let artworkURL: URL?
    /// MusicKit artwork, which library songs need since their covers have no web address.
    var artwork: Artwork?
    /// The song's ID in its source, for saving the queue.
    var songID: String?

    init(id: String, title: String, subtitle: String?, artworkURL: URL?, artwork: Artwork? = nil, songID: String? = nil) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.artworkURL = artworkURL
        self.artwork = artwork
        self.songID = songID
    }
}

/// What the active source allows, for enabling transport buttons and remote commands.
struct PlaybackCapabilities: OptionSet, Hashable, Sendable {
    let rawValue: Int
    static let skipForward = PlaybackCapabilities(rawValue: 1 << 0)
    static let skipBackward = PlaybackCapabilities(rawValue: 1 << 1)
    static let seek = PlaybackCapabilities(rawValue: 1 << 2)
    /// A live stream (radio, ambient sound) has no duration.
    static let live = PlaybackCapabilities(rawValue: 1 << 3)

    static let track: PlaybackCapabilities = [.skipForward, .skipBackward, .seek]
}

/// A song ShazamKit recognized.
public struct SongMatch: Equatable, Sendable {
    public var title: String
    public var artist: String?
    public var artworkURL: URL?
    public var appleMusicID: String?
    public var appleMusicURL: URL?
    public var webURL: URL?

    public init(title: String, artist: String? = nil, artworkURL: URL? = nil,
                appleMusicID: String? = nil, appleMusicURL: URL? = nil, webURL: URL? = nil) {
        self.title = title
        self.artist = artist
        self.artworkURL = artworkURL
        self.appleMusicID = appleMusicID
        self.appleMusicURL = appleMusicURL
        self.webURL = webURL
    }

    /// "“Title” by Artist", for spoken answers and cards.
    public var spokenDescription: String {
        if let artist, !artist.isEmpty { return "“\(title)” by \(artist)" }
        return "“\(title)”"
    }
}

/// Errors the Audio module reports to people and to the assistant.
enum AudioError: LocalizedError, Equatable {
    case musicNotAuthorized
    case noSubscription
    case nothingFound(String)
    case speakerNotFound(String)
    case musicAssistantUnavailable
    case noMusicAssistantSpeaker
    case microphoneUnavailable(String)
    case microphoneDenied
    case invalidStreamURL
    case recognitionFailed(String)

    var errorDescription: String? {
        switch self {
        case .musicNotAuthorized:
            "HomePad needs permission to use Apple Music. Open the Music app on HomePad to allow it."
        case .noSubscription:
            "Playing songs from the catalog needs an Apple Music subscription."
        case .nothingFound(let query):
            "I couldn't find anything for \"\(query)\"."
        case .speakerNotFound(let name):
            "I couldn't find a speaker called \"\(name)\"."
        case .musicAssistantUnavailable:
            "Playing music by name on that speaker needs it to be a Music Assistant player in Home Assistant."
        case .noMusicAssistantSpeaker:
            "Music Assistant has no speakers yet. Add your HomePods or Sonos as players in Music Assistant."
        case .microphoneUnavailable(let reason):
            reason
        case .microphoneDenied:
            "HomePad doesn't have microphone access. Turn it on in Settings to identify songs."
        case .invalidStreamURL:
            "That doesn't look like a stream address. Use a link that starts with http or https."
        case .recognitionFailed(let reason):
            reason
        }
    }
}
