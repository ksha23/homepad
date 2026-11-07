import Foundation
import HomePadCore

/// Something that plays audio inside HomePad: Apple Music, a radio stream or
/// sleep sounds. `AudioMediaService` keeps one active source at a time and
/// routes transport controls, Now Playing and remote commands to it.
@MainActor
protocol PlaybackSource: AnyObject {
    var kind: MediaSourceKind { get }
    /// What is loaded right now, nil when idle.
    var nowPlaying: NowPlaying? { get }
    var upNext: [QueueItem] { get }
    var capabilities: PlaybackCapabilities { get }

    func resume() async throws
    func pause()
    /// Stops and unloads. The source becomes idle.
    func stop()
    func skipForward() async
    func skipBackward() async
    func seek(to seconds: TimeInterval)
    /// Scales the source's own output level, 0...1. Used by the sleep timer fade.
    func setFadeLevel(_ level: Double)
}

extension PlaybackSource {
    var isPlaying: Bool { nowPlaying?.isPlaying ?? false }
}
