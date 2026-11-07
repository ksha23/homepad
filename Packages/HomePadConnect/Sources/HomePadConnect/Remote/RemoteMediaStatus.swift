import Foundation
import HomePadCore

/// A HomePad's music as a companion sees it: what plays, where, how loud, and
/// the speakers it can move to. Body of a `.mediaStatus` message, which a
/// HomePad pushes to companions that sent `media.subscribe`.
///
/// Kinds travel as text rather than Core's enums, so a source or speaker kind a
/// newer HomePad adds never stops an older companion from reading the rest.
/// A cover that only the HomePad can read (a file) rides as the message's
/// attachment, sent again only when `Track.artworkKey` changes.
public struct RemoteMediaStatus: Codable, Equatable, Sendable {
    /// The item that plays or is paused.
    public struct Track: Codable, Equatable, Sendable {
        public var title: String
        public var artist: String?
        public var album: String?
        /// A web cover the companion loads itself. Nil for covers sent as an attachment.
        public var artworkURL: URL?
        /// Names the cover, so a companion keeps the image it has while the cover stays the same.
        public var artworkKey: String?
        public var duration: Double?
        /// Seconds played when the HomePad sent this status.
        public var elapsed: Double?
        public var isPlaying: Bool
        /// A `MediaSourceKind` raw value, such as "appleMusic" or "radio".
        public var source: String

        public init(title: String, artist: String? = nil, album: String? = nil, artworkURL: URL? = nil,
                    artworkKey: String? = nil, duration: Double? = nil, elapsed: Double? = nil,
                    isPlaying: Bool, source: String) {
            self.title = title
            self.artist = artist
            self.album = album
            self.artworkURL = artworkURL
            self.artworkKey = artworkKey
            self.duration = duration
            self.elapsed = elapsed
            self.isPlaying = isPlaying
            self.source = source
        }

        /// The source, or nil for one this companion does not know.
        public var sourceKind: MediaSourceKind? { MediaSourceKind(rawValue: source) }

        /// "Artist · Album", or whichever of them is known.
        public var subtitle: String? {
            let parts = [artist, album].compactMap { $0 }.filter { !$0.isEmpty }
            return parts.isEmpty ? nil : parts.joined(separator: " · ")
        }

        /// Where playback is `interval` seconds after this status arrived.
        public func position(after interval: TimeInterval) -> Double? {
            guard let elapsed else { return nil }
            let moved = isPlaying ? elapsed + max(0, interval) : elapsed
            return duration.map { min(moved, $0) } ?? moved
        }
    }

    /// A place the HomePad can play: its own route or a speaker it controls.
    public struct Output: Codable, Equatable, Sendable, Identifiable {
        public var id: String
        public var name: String
        /// An `AudioOutputKind` raw value, such as "airPlay" or "homeAssistantPlayer".
        public var kind: String
        /// In use: this iPad's route, or a speaker that has something of its own loaded.
        public var isActive: Bool
        /// Plays the music this status shows.
        public var isCurrent: Bool

        public init(id: String, name: String, kind: String, isActive: Bool, isCurrent: Bool) {
            self.id = id
            self.name = name
            self.kind = kind
            self.isActive = isActive
            self.isCurrent = isCurrent
        }

        /// The kind, or nil for one this companion does not know.
        public var outputKind: AudioOutputKind? { AudioOutputKind(rawValue: kind) }
    }

    /// The `RemoteProtocol` version of the HomePad that sent this.
    public var version: Int
    /// Nil when nothing is playing or paused.
    public var track: Track?
    /// Where the music plays, for example "Kitchen HomePod" or "Living Room and Kitchen".
    public var routeName: String
    public var outputs: [Output]
    /// The level `MediaCommand.setVolume` changes, 0 to 1, when the HomePad knows it.
    public var volume: Double?
    /// True when `MediaCommand.seek` works for what plays now.
    public var canSeek: Bool

    public init(version: Int = RemoteProtocol.current, track: Track?, routeName: String, outputs: [Output],
                volume: Double?, canSeek: Bool) {
        self.version = version
        self.track = track
        self.routeName = routeName
        self.outputs = outputs
        self.volume = volume
        self.canSeek = canSeek
    }

    /// Builds the status from what `services.media` reports.
    public init(nowPlaying: NowPlaying?, outputs: [AudioOutput], routeName: String, volume: Double?, canSeek: Bool) {
        let track = nowPlaying.map { item in
            Track(title: item.title, artist: item.artist, album: item.album,
                  artworkURL: RemoteArtwork.webURL(for: item.artworkURL), artworkKey: RemoteArtwork.key(for: item.artworkURL),
                  duration: item.duration.flatMap(Self.finite), elapsed: item.elapsed.flatMap(Self.finite),
                  isPlaying: item.isPlaying, source: item.source.rawValue)
        }
        let current = Self.currentOutputIDs(nowPlaying: nowPlaying, outputs: outputs)
        self.init(
            track: track,
            routeName: nowPlaying?.outputName ?? routeName,
            outputs: outputs.map {
                Output(id: $0.id, name: $0.name, kind: $0.kind.rawValue, isActive: $0.isActive, isCurrent: current.contains($0.id))
            },
            volume: track == nil ? nil : volume.map { max(0, min(1, $0)) },
            canSeek: track != nil && canSeek
        )
    }

    /// Speakers the music plays on right now.
    public var currentOutputs: [Output] { outputs.filter(\.isCurrent) }

    /// The outputs that play `nowPlaying`: the Home Assistant speaker it names
    /// when it plays on one, else this iPad's own route. A speaker that is on
    /// with music of its own is active, but not current.
    static func currentOutputIDs(nowPlaying: NowPlaying?, outputs: [AudioOutput]) -> Set<String> {
        if let nowPlaying, nowPlaying.source == .homeAssistant {
            return Set(outputs.filter { $0.kind == .homeAssistantPlayer && $0.name == nowPlaying.outputName }.map(\.id))
        }
        return Set(outputs.filter { $0.kind != .homeAssistantPlayer && $0.isActive }.map(\.id))
    }

    /// JSON has no infinity or NaN, and a live stream reports an infinite duration.
    private static func finite(_ value: Double) -> Double? {
        value.isFinite && value >= 0 ? value : nil
    }
}
