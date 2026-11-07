import Foundation
import HomePadCore
import HomePadUI
import Observation

/// On a HomePad: pushes `RemoteMediaStatus` to the companions that watch its
/// music, whenever something changes, so a phone never has to ask again and again.
///
/// It works only while someone watches. Changes arrive through Observation
/// (`services.media` and the system volume are observable). Players move their
/// position without announcing it, so a check every few seconds catches a jump
/// (someone scrubbing on the iPad). Steady progress is not news: the companion
/// moves the time on by itself.
@MainActor
final class MediaStatusPublisher {
    typealias Deliver = @MainActor (PeerMessage, String) async -> Void

    /// How often to look for changes Observation cannot see.
    static let checkInterval: Duration = .seconds(2)
    /// A position further than this from where it should be is a jump worth sending.
    nonisolated static let positionTolerance: TimeInterval = 2.5

    private let services: AppServices
    private let link: PeerLink
    /// Sends one message to one device. The link by default, a recorder in tests.
    var deliver: Deliver
    /// The level `setVolume` changes on this iPad. Replaced in tests.
    var systemVolume: @MainActor () -> Double? = { SystemVolumeLevel.shared.level }

    /// Devices watching the music.
    private(set) var watchers: Set<String> = []
    private var lastSent: RemoteMediaStatus?
    private var lastSentAt = Date.distantPast
    /// The cover each watcher already has, so a cover travels once per watcher.
    private var coverSent: [String: String] = [:]
    private var cover: (key: String, data: Data)?
    private var checkTask: Task<Void, Never>?
    private var pendingTask: Task<Void, Never>?
    /// Publishes run one after another, so a newer status never arrives before an older one.
    private var queue: Task<Void, Never>?
    /// Bumped whenever watching starts or ends, so an old observation stops re-arming.
    private var generation = 0

    init(services: AppServices, link: PeerLink) {
        self.services = services
        self.link = link
        self.deliver = { [weak link] message, peerID in
            try? await link?.send(message, to: peerID)
        }
    }

    func start() {
        link.on(.mediaSubscribe) { [weak self] message, peer in
            guard let body = try? message.content(MediaSubscription.self) else { return }
            if body.isWatching {
                self?.watch(peer.id)
            } else {
                self?.stopWatching(peer.id)
            }
        }
        link.onDisconnect { [weak self] peerID in self?.stopWatching(peerID) }
    }

    // MARK: Watchers

    /// Starts pushing to `peerID`, beginning with the current status and cover.
    func watch(_ peerID: String) {
        let isFirst = watchers.isEmpty
        watchers.insert(peerID)
        coverSent[peerID] = nil
        let status = snapshot()
        if isFirst {
            beginWatching()
            lastSent = status
            lastSentAt = Date()
        }
        enqueue { await self.publish(status, to: [peerID]) }
    }

    func stopWatching(_ peerID: String) {
        guard watchers.remove(peerID) != nil else { return }
        coverSent[peerID] = nil
        if watchers.isEmpty { endWatching() }
    }

    private func beginWatching() {
        generation += 1
        observeChanges(generation: generation)
        checkTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: Self.checkInterval)
                guard let self else { return }
                self.publishIfChanged()
            }
        }
    }

    private func endWatching() {
        generation += 1
        checkTask?.cancel()
        checkTask = nil
        pendingTask?.cancel()
        pendingTask = nil
        lastSent = nil
        cover = nil
    }

    /// Re-arms after each change while the same watching period lasts.
    private func observeChanges(generation: Int) {
        guard generation == self.generation, !watchers.isEmpty else { return }
        withObservationTracking {
            _ = snapshot()
        } onChange: { [weak self] in
            Task { @MainActor in
                guard let self, generation == self.generation else { return }
                self.observeChanges(generation: generation)
                self.publishSoon()
            }
        }
    }

    // MARK: Publishing

    /// Publishes shortly, once a burst of changes (a skip, a volume drag) settles.
    func publishSoon() {
        guard !watchers.isEmpty else { return }
        pendingTask?.cancel()
        pendingTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(150))
            guard !Task.isCancelled else { return }
            self?.publishIfChanged()
        }
    }

    /// Sends the current status to every watcher when it is news.
    func publishIfChanged() {
        guard !watchers.isEmpty else { return }
        let status = snapshot()
        guard Self.isNews(status, since: lastSent, after: Date().timeIntervalSince(lastSentAt)) else { return }
        lastSent = status
        lastSentAt = Date()
        let peers = watchers
        enqueue { await self.publish(status, to: peers) }
    }

    /// What `services.media` reports now.
    func snapshot() -> RemoteMediaStatus {
        let media = services.media
        let nowPlaying = media.nowPlaying
        let outputs = media.outputs
        return RemoteMediaStatus(
            nowPlaying: nowPlaying, outputs: outputs, routeName: media.currentRouteName,
            volume: Self.volume(nowPlaying: nowPlaying, outputs: outputs, system: media.speakerVolume ?? systemVolume()),
            canSeek: (media as? any MediaSeeking)?.canSeek == true
        )
    }

    private func publish(_ status: RemoteMediaStatus, to peers: Set<String>) async {
        let key = status.track?.artworkKey
        let coverData = status.track?.artworkURL == nil ? await coverData(key: key) : nil
        for peer in peers where watchers.contains(peer) {
            let attaches = coverData != nil && coverSent[peer] != key
            guard let message = try? link.message(.mediaStatus, status, attachment: attaches ? coverData : nil) else { continue }
            if attaches { coverSent[peer] = key }
            await deliver(message, peer)
        }
    }

    /// Returns once every status queued so far has gone out.
    func waitUntilSent() async {
        await queue?.value
    }

    private func enqueue(_ work: @escaping @MainActor () async -> Void) {
        let previous = queue
        queue = Task { @MainActor in
            await previous?.value
            await work()
        }
    }

    /// The current cover as a small JPEG, made once per cover.
    private func coverData(key: String?) async -> Data? {
        guard let key else { return nil }
        if let cover, cover.key == key { return cover.data }
        guard let file = services.media.nowPlaying?.artworkURL, RemoteArtwork.needsAttachment(file),
              RemoteArtwork.key(for: file) == key, let data = await RemoteArtwork.attachment(from: file) else { return nil }
        cover = (key, data)
        return data
    }

    // MARK: Rules

    /// True when `new` differs from `old` in more than the clock moving on.
    nonisolated static func isNews(_ new: RemoteMediaStatus, since old: RemoteMediaStatus?, after interval: TimeInterval) -> Bool {
        guard let old else { return true }
        var newWithoutTime = new
        var oldWithoutTime = old
        newWithoutTime.track?.elapsed = nil
        oldWithoutTime.track?.elapsed = nil
        if newWithoutTime != oldWithoutTime { return true }
        guard let position = new.track?.elapsed, let expected = old.track?.position(after: interval) else {
            return (new.track?.elapsed == nil) != (old.track?.elapsed == nil)
        }
        return abs(position - expected) > positionTolerance
    }

    /// The level `MediaService.setVolume` changes: a Home Assistant speaker's own
    /// volume when the music plays on one, else `system`, which is the AirPlay
    /// speakers' volume while Apple's player plays to them and this iPad's
    /// otherwise. Nil when nothing plays.
    nonisolated static func volume(nowPlaying: NowPlaying?, outputs: [AudioOutput], system: Double?) -> Double? {
        guard let nowPlaying else { return nil }
        if nowPlaying.source == .homeAssistant {
            return outputs.first { $0.kind == .homeAssistantPlayer && $0.name == nowPlaying.outputName }?.volume
        }
        return system
    }
}
