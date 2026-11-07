import Foundation
import HomePadCore

/// Keeps Now Playing steady through track changes. While a player skips, it often
/// reports nothing, a paused state, or a track without artwork or duration for a
/// moment. Screens that read those transient values jump between layouts. This
/// holds the last item for `window` seconds instead:
///
/// - Nothing playing: the previous item stays until nothing has been reported for `window`.
/// - A paused report right after a track change keeps showing playing until `window` passes.
/// - The same track with missing artwork, album or duration keeps the values it had.
///
/// It is a value type with explicit times, so the rules are unit tested.
struct NowPlayingHold {
    /// How long transitional states are held, in seconds.
    let window: TimeInterval
    /// The last real item seen, with gaps filled.
    private(set) var last: NowPlaying?
    /// When reports turned to nothing, while `last` is still shown.
    private(set) var emptySince: Date?
    /// When the title last changed.
    private(set) var trackChangedAt: Date?
    /// Whether the previous track was playing when the title changed.
    private(set) var wasPlayingBeforeChange = false

    init(window: TimeInterval = 1.25) {
        self.window = window
    }

    /// Records a new report. Call whenever the underlying value changes.
    mutating func observe(_ raw: NowPlaying?, at now: Date) {
        guard let raw else {
            if last != nil, emptySince == nil { emptySince = now }
            return
        }
        emptySince = nil
        if !Self.isSameTrack(raw, last) {
            wasPlayingBeforeChange = last?.isPlaying ?? false
            trackChangedAt = now
        }
        last = filled(raw)
    }

    /// What screens should show for the current report at `now`.
    func resolve(_ raw: NowPlaying?, at now: Date) -> NowPlaying? {
        guard let raw else {
            guard let last else { return nil }
            guard let emptySince else { return last }
            return now.timeIntervalSince(emptySince) < window ? last : nil
        }
        var shown = filled(raw)
        if !raw.isPlaying {
            // A new track that has not started yet, seen before or after `observe`.
            let unobservedChange = last?.isPlaying == true && !Self.isSameTrack(raw, last)
            let recentChange = wasPlayingBeforeChange
                && trackChangedAt.map { now.timeIntervalSince($0) < window } == true
            if unobservedChange || recentChange { shown.isPlaying = true }
        }
        return shown
    }

    /// When the held state ends, so the owner can refresh the screen then. Nil when nothing is held.
    func expiry(after now: Date) -> Date? {
        let ends = [emptySince, trackChangedAt].compactMap { $0?.addingTimeInterval(window) }.filter { $0 > now }
        return ends.min()
    }

    /// Fills artwork, album and duration from the previous report of the same track.
    private func filled(_ raw: NowPlaying) -> NowPlaying {
        guard let last, Self.isSameTrack(raw, last) else { return raw }
        var item = raw
        item.artworkURL = raw.artworkURL ?? last.artworkURL
        item.album = raw.album ?? last.album
        item.duration = raw.duration ?? last.duration
        item.artist = raw.artist ?? last.artist
        return item
    }

    private static func isSameTrack(_ lhs: NowPlaying, _ rhs: NowPlaying?) -> Bool {
        guard let rhs else { return false }
        return lhs.title == rhs.title && lhs.source == rhs.source
    }
}
