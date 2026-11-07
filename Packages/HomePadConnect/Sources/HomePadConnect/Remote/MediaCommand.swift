import Foundation

/// Music control a companion asks a HomePad for. Travels inside
/// `RemoteCommand.media(command:)` and runs through the HomePad's `services.media`.
public enum MediaCommand: Codable, Equatable, Sendable {
    case play
    case pause
    case nextTrack
    case previousTrack
    /// Jumps to a position in the current item, when the HomePad reports `canSeek`.
    case seek(seconds: Double)
    /// Volume of whatever the HomePad's music plays on, 0 to 1.
    case setVolume(level: Double)
    /// Moves the music to one of the HomePad's outputs (`RemoteMediaStatus.outputs`).
    case selectOutput(id: String)
    /// Searches the HomePad's music and plays the best match, as "play jazz" does.
    case playSearch(query: String)

    /// Longest search a HomePad accepts.
    public static let maxQueryLength = 200
}
