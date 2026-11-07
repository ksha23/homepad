import Foundation

/// Picks the cover to show while MusicKit loads a skipped-to song's artwork.
///
/// After a skip MusicKit often gives the new song a stand-in cover (one address
/// shared by every song) and the real one a second or two later, sometimes only
/// when asked again. Drawing the stand-in showed black or an earlier song's cover.
/// This keeps the previous cover for `window`, so a quick load crossfades once,
/// and after that shows no cover (the song's generated one) rather than another
/// song's.
///
/// Generic over the cover type and a value type with explicit times, like
/// `NowPlayingHold`, so the rules are unit tested without MusicKit.
struct CoverHold<Cover: Equatable> {
    let window: TimeInterval
    /// The queue entry the last update was for.
    private(set) var entryID: String?
    /// The cover on screen.
    private(set) var shown: Cover?
    /// The entry whose own cover `shown` is. Only the entry just before may lend it.
    private(set) var ownerID: String?
    /// When the current entry started waiting for its real cover.
    private(set) var waitingSince: Date?

    init(window: TimeInterval = 1.0) {
        self.window = window
    }

    /// The cover to show now.
    /// - Parameters:
    ///   - real: The entry's real cover, or nil while only a stand-in or nothing is known.
    ///   - isLoading: True when the entry has a stand-in, so a real cover is coming.
    mutating func update(entryID: String, real: Cover?, isLoading: Bool, at now: Date) -> Cover? {
        let previousEntryID = self.entryID
        self.entryID = entryID
        if let real {
            shown = real
            ownerID = entryID
            waitingSince = nil
            return real
        }
        guard isLoading else {
            clear()
            return nil
        }
        if entryID != previousEntryID {
            waitingSince = now
            // A quick second skip must not bring back a cover from two songs ago.
            if ownerID != previousEntryID { clear() }
        } else if waitingSince == nil {
            waitingSince = now
        }
        if let waitingSince, now.timeIntervalSince(waitingSince) >= window {
            shown = nil
            ownerID = nil
        }
        return shown
    }

    private mutating func clear() {
        shown = nil
        ownerID = nil
        waitingSince = nil
    }

    /// When the previous cover gives way, so the owner can update the screen then.
    func expiry(after now: Date) -> Date? {
        guard shown != nil, let ends = waitingSince?.addingTimeInterval(window), ends > now else { return nil }
        return ends
    }

    /// Forgets everything, when playback stops or a new queue starts.
    mutating func reset() {
        self = CoverHold(window: window)
    }
}
