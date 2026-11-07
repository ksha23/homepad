import AVFoundation
import HomePadCore
import Observation

/// Plays internet radio streams with `AVPlayer` and reads the song title from
/// the stream's ICY metadata, so Now Playing shows "Artist – Song" instead of
/// only the station name.
@MainActor
@Observable
final class RadioPlayer: PlaybackSource {
    let kind = MediaSourceKind.radio
    private(set) var station: RadioStation?
    private(set) var song: (title: String, artist: String?)?
    private(set) var isBuffering = false
    private(set) var lastError: String?
    private var playing = false
    private var fadeLevel = 1.0

    @ObservationIgnored private let player = AVPlayer()
    @ObservationIgnored private let metadata = StreamMetadataReader()
    @ObservationIgnored private var statusObservation: NSKeyValueObservation?
    private let log = Log.make("Radio")

    init() {
        player.automaticallyWaitsToMinimizeStalling = true
        statusObservation = player.observe(\.timeControlStatus, options: [.new]) { [weak self] player, _ in
            let status = player.timeControlStatus
            Task { @MainActor in self?.update(status) }
        }
        metadata.onStreamTitle = { [weak self] text in
            self?.song = StreamParsing.songInfo(fromStreamTitle: text)
        }
    }

    var nowPlaying: NowPlaying? {
        guard let station else { return nil }
        if let song {
            return NowPlaying(title: song.title, artist: song.artist ?? station.name, album: station.name,
                              artworkURL: station.artworkURL, isPlaying: playing, source: .radio)
        }
        return NowPlaying(title: station.name, artist: isBuffering ? "Connecting…" : station.subtitle,
                          artworkURL: station.artworkURL, isPlaying: playing, source: .radio)
    }

    var upNext: [QueueItem] { [] }
    var capabilities: PlaybackCapabilities { .live }

    /// Starts a station from the live edge.
    func play(_ station: RadioStation) async throws {
        let url = try await Self.playableURL(for: station.streamURL)
        self.station = station
        song = nil
        lastError = nil
        load(url)
        player.play()
        log.info("Playing station \(station.name, privacy: .public)")
    }

    func resume() async throws {
        guard let station else { return }
        // Live radio resumes at the live edge, not where it paused.
        try await play(station)
    }

    func pause() {
        player.pause()
    }

    func stop() {
        player.pause()
        player.replaceCurrentItem(with: nil)
        station = nil
        song = nil
        playing = false
        isBuffering = false
    }

    func skipForward() async {}
    func skipBackward() async {}
    func seek(to seconds: TimeInterval) {}

    func setFadeLevel(_ level: Double) {
        fadeLevel = max(0, min(1, level))
        player.volume = Float(fadeLevel)
    }

    private func load(_ url: URL) {
        let item = AVPlayerItem(url: url)
        metadata.attach(to: item)
        player.replaceCurrentItem(with: item)
        player.volume = Float(fadeLevel)
    }

    private func update(_ status: AVPlayer.TimeControlStatus) {
        playing = status != .paused
        isBuffering = status == .waitingToPlayAtSpecifiedRate
        if let error = player.currentItem?.error {
            lastError = error.localizedDescription
            log.error("Stream failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Resolves .pls and .m3u playlist links to their first stream. Other URLs pass through.
    static func playableURL(for url: URL) async throws -> URL {
        guard StreamParsing.isPlaylistURL(url) else { return url }
        let (data, _) = try await URLSession.shared.data(from: url)
        return StreamParsing.firstStreamURL(inPlaylist: String(decoding: data, as: UTF8.self)) ?? url
    }
}

/// Receives timed metadata from a radio stream and reports the stream title.
private final class StreamMetadataReader: NSObject, AVPlayerItemMetadataOutputPushDelegate {
    var onStreamTitle: (@MainActor (String) -> Void)?

    func attach(to item: AVPlayerItem) {
        let output = AVPlayerItemMetadataOutput(identifiers: nil)
        output.setDelegate(self, queue: .main)
        item.add(output)
    }

    func metadataOutput(_ output: AVPlayerItemMetadataOutput, didOutputTimedMetadataGroups groups: [AVTimedMetadataGroup],
                        from track: AVPlayerItemTrack?) {
        let titleItems = groups.flatMap(\.items).filter {
            $0.identifier == .icyMetadataStreamTitle || $0.commonKey == .commonKeyTitle
        }
        guard let item = titleItems.first else { return }
        Task { @MainActor [weak self] in
            guard let text = try? await item.load(.stringValue) else { return }
            self?.onStreamTitle?(text)
        }
    }
}
