import Foundation
import HomePadCore
import MediaPlayer
import Observation

/// Plays library items with MediaPlayer's `applicationQueuePlayer`, Apple's own player
/// for in-app queues. Like `ApplicationMusicPlayer` it has its own audio session and
/// AirPlay route, so HomePad claims no session for it, and it works without a
/// MusicKit token.
@MainActor
@Observable
final class MediaLibraryPlayer: PlaybackSource {
    let kind = MediaSourceKind.appleMusic

    /// What plays. Like `AppleMusicPlayer.nowPlaying`, observers hear about every
    /// change except the progress task's once-a-second `elapsed`, which only the
    /// scrubber shows, on its own timeline.
    private(set) var nowPlaying: NowPlaying? {
        get {
            access(keyPath: \.nowPlaying)
            return shown
        }
        set {
            guard newValue != shown else { return }
            withMutation(keyPath: \.nowPlaying) { shown = newValue }
        }
    }
    /// The queue is not readable from `applicationQueuePlayer`, so Up Next stays empty.
    let upNext: [QueueItem] = []
    /// Artwork of the current song. Library artwork has no URL.
    private(set) var currentArtwork: MPMediaItemArtwork?
    var capabilities: PlaybackCapabilities { .track }

    @ObservationIgnored private var shown: NowPlaying?
    @ObservationIgnored private var observers: [NSObjectProtocol] = []
    @ObservationIgnored private var progressTask: Task<Void, Never>?

    private var player: MPMusicPlayerApplicationController { .applicationQueuePlayer }

    func play(_ collection: MPMediaItemCollection) async throws {
        observe()
        player.setQueue(with: collection)
        try await player.prepareToPlay()
        player.play()
        refresh()
    }

    func resume() async throws {
        player.play()
        refresh()
    }

    func pause() {
        guard nowPlaying != nil else { return }
        player.pause()
        refresh()
    }

    func stop() {
        guard nowPlaying != nil else { return }
        player.stop()
        nowPlaying = nil
        currentArtwork = nil
        progressTask?.cancel()
        progressTask = nil
    }

    func skipForward() async {
        player.skipToNextItem()
        refresh()
    }

    /// Restarts the song when more than a few seconds in, like the Music app.
    func skipBackward() async {
        if player.currentPlaybackTime > 3 { player.skipToBeginning() } else { player.skipToPreviousItem() }
        refresh()
    }

    func seek(to seconds: TimeInterval) {
        player.currentPlaybackTime = max(0, seconds)
        refresh()
    }

    /// The player has no volume of its own, so the sleep timer pauses it at the end instead.
    func setFadeLevel(_ level: Double) {}

    private func observe() {
        guard observers.isEmpty else { return }
        player.beginGeneratingPlaybackNotifications()
        for name in [Notification.Name.MPMusicPlayerControllerNowPlayingItemDidChange, .MPMusicPlayerControllerPlaybackStateDidChange] {
            observers.append(NotificationCenter.default.addObserver(forName: name, object: player, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.refresh() }
            })
        }
    }

    private func refresh() {
        guard let item = player.nowPlayingItem else {
            nowPlaying = nil
            currentArtwork = nil
            return
        }
        let isPlaying = player.playbackState == .playing
        nowPlaying = NowPlaying(
            title: item.title ?? "Unknown Song", artist: item.artist, album: item.albumTitle,
            duration: item.playbackDuration > 0 ? item.playbackDuration : nil,
            elapsed: player.currentPlaybackTime, isPlaying: isPlaying, source: .appleMusic
        )
        currentArtwork = item.artwork
        if isPlaying { trackProgress() } else { progressTask?.cancel(); progressTask = nil }
    }

    /// Keeps `elapsed` current for the scrubber while playing, without telling observers.
    private func trackProgress() {
        guard progressTask == nil else { return }
        progressTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard let self, self.nowPlaying?.isPlaying == true else { return }
                self.shown?.elapsed = self.player.currentPlaybackTime
            }
        }
    }
}
