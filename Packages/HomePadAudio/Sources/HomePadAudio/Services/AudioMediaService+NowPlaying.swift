import Foundation
import HomePadCore

/// Feeds the Now Playing holds and the system Now Playing bridge as what plays changes.
extension AudioMediaService {
    /// Feeds the hold and re-publishes to Control Center whenever Now Playing changes.
    func trackNowPlaying() {
        let (raw, localIsPlaying, live, snapshot) = withObservationTracking {
            let live = liveNowPlaying
            return (rawFocus, activeSource?.isPlaying == true, live, BridgeSnapshot(
                nowPlaying: live, capabilities: focus == .local ? activeSource?.capabilities ?? [] : [],
                publishesInfo: focus == .local && [.radio, .ambient, .demo].contains(activeKind)
            ))
        } onChange: { [weak self] in
            Task { @MainActor in self?.trackNowPlaying() }
        }
        let now = Date()
        focusHold.observe(raw, localIsPlaying: localIsPlaying, at: now)
        hold.observe(live, at: now)
        if let url = live?.artworkURL { ArtworkWash.prepare(url) }
        scheduleHoldExpiry(after: now)
        guard snapshot.isMeaningfullyDifferent(from: lastBridgeSnapshot) else { return }
        lastBridgeSnapshot = snapshot
        bridge?.update(snapshot.nowPlaying, capabilities: snapshot.capabilities, publishesInfo: snapshot.publishesInfo)
    }

    /// Refreshes screens when a held state ends.
    private func scheduleHoldExpiry(after now: Date) {
        holdTask?.cancel()
        guard let expiry = [hold.expiry(after: now), focusHold.expiry(after: now)].compactMap({ $0 }).min() else { return }
        holdTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(expiry.timeIntervalSince(now) + 0.05))
            guard !Task.isCancelled else { return }
            self?.holdRevision += 1
        }
    }
}
