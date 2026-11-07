import Foundation

/// Keeps Now Playing on the same player through a track change. While a player
/// skips, it reports "paused" for a moment, so the focus rules fall through to
/// another speaker that is playing elsewhere in the house, and every screen
/// flashes that speaker's track before coming back. This holds the previous
/// focus for `window` seconds instead. Local audio that is really playing takes
/// focus at once, so starting music on the iPad is never delayed.
///
/// A value type with explicit times, like `NowPlayingHold`, so the rules are unit tested.
struct FocusHold {
    typealias Focus = AudioMediaService.Focus

    let window: TimeInterval
    /// The focus screens follow.
    private(set) var held: Focus?
    /// When the rules first picked something other than `held`.
    private(set) var lostAt: Date?

    init(window: TimeInterval = 1.25) {
        self.window = window
    }

    /// Records the focus the rules pick now. Call whenever it may have changed.
    mutating func observe(_ raw: Focus?, localIsPlaying: Bool, at now: Date) {
        if raw == held || held == nil || (raw == .local && localIsPlaying) {
            held = raw
            lostAt = nil
            return
        }
        if lostAt == nil { lostAt = now }
        if let lostAt, now.timeIntervalSince(lostAt) >= window {
            held = raw
            self.lostAt = nil
        }
    }

    /// The focus to use at `now`.
    func resolve(_ raw: Focus?, localIsPlaying: Bool, at now: Date) -> Focus? {
        if raw == held || held == nil || (raw == .local && localIsPlaying) { return raw }
        // A change not observed yet is just starting, so it is held too.
        guard let lostAt else { return held }
        return now.timeIntervalSince(lostAt) < window ? held : raw
    }

    /// When the held focus lets go, so the owner can refresh screens then.
    func expiry(after now: Date) -> Date? {
        guard let ends = lostAt?.addingTimeInterval(window), ends > now else { return nil }
        return ends
    }
}
