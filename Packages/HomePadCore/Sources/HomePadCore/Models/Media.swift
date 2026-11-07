import Foundation

public enum MediaSourceKind: String, Codable, Sendable {
    case appleMusic       // MusicKit inside HomePad
    case radio            // internet radio stream inside HomePad
    case podcast
    case homeAssistant    // a Home Assistant / Music Assistant media_player entity
    case ambient          // generated sleep and ambient sounds
    case system           // something else the system reports
}

public struct NowPlaying: Equatable, Sendable {
    public var title: String
    public var artist: String?
    public var album: String?
    public var artworkURL: URL?
    public var duration: TimeInterval?
    public var elapsed: TimeInterval?
    public var isPlaying: Bool
    public var source: MediaSourceKind
    /// Where the audio is coming out, for example "Kitchen HomePod".
    public var outputName: String?
    /// Time-synced lyrics lines if available.
    public var lyrics: [LyricLine]

    public init(
        title: String, artist: String? = nil, album: String? = nil, artworkURL: URL? = nil,
        duration: TimeInterval? = nil, elapsed: TimeInterval? = nil, isPlaying: Bool = false,
        source: MediaSourceKind = .system, outputName: String? = nil, lyrics: [LyricLine] = []
    ) {
        self.title = title
        self.artist = artist
        self.album = album
        self.artworkURL = artworkURL
        self.duration = duration
        self.elapsed = elapsed
        self.isPlaying = isPlaying
        self.source = source
        self.outputName = outputName
        self.lyrics = lyrics
    }
}

public struct LyricLine: Equatable, Sendable, Codable {
    public var time: TimeInterval
    public var text: String
    public init(time: TimeInterval, text: String) {
        self.time = time
        self.text = text
    }
}

public enum AudioOutputKind: String, Codable, Sendable {
    case builtInSpeaker
    case airPlay
    case bluetooth
    case wired
    case homeAssistantPlayer
}

/// A place sound can go. AirPlay outputs come from the system route;
/// Home Assistant players (HomePods via Music Assistant, Sonos) are controlled remotely.
public struct AudioOutput: Identifiable, Hashable, Sendable {
    public var id: String
    public var name: String
    public var kind: AudioOutputKind
    public var isActive: Bool
    public var volume: Double?

    public init(id: String, name: String, kind: AudioOutputKind, isActive: Bool = false, volume: Double? = nil) {
        self.id = id
        self.name = name
        self.kind = kind
        self.isActive = isActive
        self.volume = volume
    }
}

/// What a system volume slider shows once the finger lifts.
///
/// AirPlay speakers report a new volume late or not at all, so the slider went
/// back to the old level after a drag although the HomePod had changed. The
/// chosen level holds until the system reports it, or until any report arrives
/// after `hold`, which means the volume changed elsewhere (hardware buttons,
/// Control Center). Reports during the hold are echoes of the drag.
public struct HeldVolume: Equatable, Sendable {
    /// The last level the system reported.
    public private(set) var reported: Double
    private var chosen: Double?
    private var chosenAt = Date.distantPast
    public var hold: TimeInterval
    /// Reports this close to the chosen level confirm it. The system rounds
    /// volume to its own steps.
    public var tolerance = 0.04

    public init(reported: Double, hold: TimeInterval = 2) {
        self.reported = reported
        self.hold = hold
    }

    /// The level to show.
    public var level: Double { chosen ?? reported }

    /// Someone set the volume here.
    public mutating func choose(_ value: Double, at now: Date) {
        chosen = value
        chosenAt = now
    }

    /// The system reported a level.
    public mutating func report(_ value: Double, at now: Date) {
        reported = value
        guard let chosen else { return }
        if abs(value - chosen) <= tolerance || now.timeIntervalSince(chosenAt) > hold {
            self.chosen = nil
        }
    }
}
