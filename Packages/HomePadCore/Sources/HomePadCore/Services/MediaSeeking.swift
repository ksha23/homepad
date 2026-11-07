import Foundation

/// A `MediaService` that can jump within what plays. Optional, so a media
/// service without it still works. Callers check `services.media as? any MediaSeeking`
/// and then `canSeek`, as the iPhone companion's scrubber does through a HomePad.
@MainActor
public protocol MediaSeeking: MediaService {
    /// True when what plays now can jump to a position (a song can, live radio cannot).
    var canSeek: Bool { get }
    /// Jumps to `seconds` from the start of what plays.
    func seek(to seconds: TimeInterval) async
}
