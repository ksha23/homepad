import HomePadCore
import MediaPlayer
import UIKit

/// Publishes HomePad playback to `MPNowPlayingInfoCenter` and answers
/// `MPRemoteCommandCenter`, so Control Center, the Lock Screen, an iPhone remote
/// and HomePod touch controls all work.
///
/// Apple Music is the exception for info: `ApplicationMusicPlayer` publishes its
/// own Now Playing info, so the bridge stays out of its way and only handles commands.
@MainActor
final class NowPlayingCenterBridge {
    struct Handlers {
        var play: @MainActor () async -> Void
        var pause: @MainActor () async -> Void
        var togglePlayPause: @MainActor () async -> Void
        var next: @MainActor () async -> Void
        var previous: @MainActor () async -> Void
        var seek: @MainActor (TimeInterval) -> Void
    }

    private let commands = MPRemoteCommandCenter.shared()
    private var artworkURL: URL?
    private var artwork: MPMediaItemArtwork?
    private var artworkTask: Task<Void, Never>?
    private var lastInfo: NowPlaying?

    init(handlers: Handlers) {
        register(commands.playCommand) { await handlers.play() }
        register(commands.pauseCommand) { await handlers.pause() }
        register(commands.togglePlayPauseCommand) { await handlers.togglePlayPause() }
        register(commands.stopCommand) { await handlers.pause() }
        register(commands.nextTrackCommand) { await handlers.next() }
        register(commands.previousTrackCommand) { await handlers.previous() }
        commands.changePlaybackPositionCommand.addTarget { event in
            guard let event = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            MainActor.assumeIsolated { handlers.seek(event.positionTime) }
            return .success
        }
    }

    /// Updates the system's Now Playing info and which remote commands are enabled.
    func update(_ nowPlaying: NowPlaying?, capabilities: PlaybackCapabilities, publishesInfo: Bool) {
        commands.nextTrackCommand.isEnabled = capabilities.contains(.skipForward)
        commands.previousTrackCommand.isEnabled = capabilities.contains(.skipBackward)
        commands.changePlaybackPositionCommand.isEnabled = capabilities.contains(.seek)
        let center = MPNowPlayingInfoCenter.default()
        guard publishesInfo, let nowPlaying else {
            if lastInfo != nil { center.nowPlayingInfo = nil }
            lastInfo = nil
            return
        }
        lastInfo = nowPlaying
        loadArtwork(nowPlaying.artworkURL)
        center.nowPlayingInfo = Self.info(for: nowPlaying, isLive: capabilities.contains(.live), artwork: artwork)
    }

    /// The `MPNowPlayingInfoCenter` dictionary for a `NowPlaying`.
    static func info(for nowPlaying: NowPlaying, isLive: Bool, artwork: MPMediaItemArtwork?) -> [String: Any] {
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: nowPlaying.title,
            MPNowPlayingInfoPropertyPlaybackRate: nowPlaying.isPlaying ? 1.0 : 0.0,
            MPNowPlayingInfoPropertyDefaultPlaybackRate: 1.0,
            MPNowPlayingInfoPropertyIsLiveStream: isLive,
            MPNowPlayingInfoPropertyMediaType: MPNowPlayingInfoMediaType.audio.rawValue,
        ]
        if let artist = nowPlaying.artist { info[MPMediaItemPropertyArtist] = artist }
        if let album = nowPlaying.album { info[MPMediaItemPropertyAlbumTitle] = album }
        if let duration = nowPlaying.duration { info[MPMediaItemPropertyPlaybackDuration] = duration }
        if let elapsed = nowPlaying.elapsed { info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = elapsed }
        if let artwork { info[MPMediaItemPropertyArtwork] = artwork }
        return info
    }

    private func register(_ command: MPRemoteCommand, action: @escaping @MainActor () async -> Void) {
        command.addTarget { _ in
            Task { @MainActor in await action() }
            return .success
        }
    }

    private func loadArtwork(_ url: URL?) {
        guard url != artworkURL else { return }
        artworkURL = url
        artwork = nil
        artworkTask?.cancel()
        guard let url, url.scheme?.hasPrefix("http") == true else { return }
        artworkTask = Task { [weak self] in
            guard let (data, _) = try? await URLSession.shared.data(from: url), let image = UIImage(data: data),
                  !Task.isCancelled, let self, self.artworkURL == url else { return }
            self.artwork = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
            if self.lastInfo != nil {
                MPNowPlayingInfoCenter.default().nowPlayingInfo?[MPMediaItemPropertyArtwork] = self.artwork
            }
        }
    }
}

/// What the Now Playing bridge last published. Elapsed time alone does not count
/// as a change, because the system extrapolates it from the playback rate.
struct BridgeSnapshot {
    var nowPlaying: NowPlaying?
    var capabilities: PlaybackCapabilities
    var publishesInfo: Bool

    func isMeaningfullyDifferent(from other: BridgeSnapshot?) -> Bool {
        guard let other else { return true }
        var mine = nowPlaying
        var theirs = other.nowPlaying
        let jumped = abs((mine?.elapsed ?? 0) - (theirs?.elapsed ?? 0)) > 3
        mine?.elapsed = nil
        theirs?.elapsed = nil
        return mine != theirs || capabilities != other.capabilities || publishesInfo != other.publishesInfo || jumped
    }
}
