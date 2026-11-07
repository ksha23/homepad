import Foundation
import HomePadCore
import Observation

/// A pretend Apple Music queue so Now Playing, Up Next, shuffle and repeat can
/// be checked in the simulator, which cannot play Apple Music.
@MainActor
@Observable
final class DemoPlaybackSource: PlaybackSource, QueueEditing {
    /// One queued song. Its own ID keeps a song queued twice apart.
    struct Entry: Identifiable, Equatable {
        let id = UUID().uuidString
        let track: DemoMusicCatalog.Track
    }

    let kind = MediaSourceKind.appleMusic
    private(set) var queue: [Entry]
    private(set) var index = 4
    private var playing: Bool
    private var elapsed: TimeInterval = 118
    private(set) var shuffle = false
    private(set) var repeatMode: MusicRepeatMode = .off
    private(set) var queueOrigin: String? = "Playing from Kitchen Radio"

    init(isPlaying: Bool) {
        playing = isPlaying
        queue = DemoMusicCatalog.tracks.map { Entry(track: $0) }
    }

    var nowPlaying: NowPlaying? {
        guard queue.indices.contains(index) else { return nil }
        let track = queue[index].track
        return NowPlaying(title: track.title, artist: track.artist, album: track.album,
                          artworkURL: AudioDemo.artworkURL(for: track.album), duration: track.duration,
                          elapsed: elapsed, isPlaying: playing, source: .appleMusic)
    }

    var upNext: [QueueItem] {
        queue.dropFirst(index + 1).prefix(AppleMusicPlayer.upNextLength).map {
            QueueItem(id: $0.id, title: $0.track.title, subtitle: $0.track.artist,
                      artworkURL: AudioDemo.artworkURL(for: $0.track.album), songID: $0.track.title)
        }
    }

    var capabilities: PlaybackCapabilities { .track }
    var queueAbilities: QueueAbilities { .all }

    func resume() async throws { playing = true }
    func pause() { playing = false }
    func stop() { playing = false }
    func seek(to seconds: TimeInterval) { elapsed = seconds }
    func setFadeLevel(_ level: Double) {}

    func skipForward() async {
        if repeatMode == .one { elapsed = 0; return }
        if index + 1 < queue.count {
            index += 1
        } else if repeatMode == .all {
            index = 0
        }
        elapsed = 0
    }

    func skipBackward() async {
        index = max(0, index - 1)
        elapsed = 0
    }

    // MARK: Playing

    /// Starts the songs an album, playlist, artist or song name stands for.
    func play(matching text: String, shuffled: Bool = false) {
        let tracks = DemoMusicCatalog.tracks(matching: text)
        play(tracks, origin: tracks.count > 1 ? text : nil, shuffled: shuffled)
    }

    func play(_ tracks: [DemoMusicCatalog.Track], startingAt start: Int = 0, origin: String?, shuffled: Bool = false) {
        guard !tracks.isEmpty else { return }
        let ordered = shuffled ? tracks.shuffled() : tracks
        queue = ordered.map { Entry(track: $0) }
        index = shuffled ? 0 : min(start, queue.count - 1)
        shuffle = shuffled
        queueOrigin = origin.map { "Playing from \($0)" }
        elapsed = 0
        playing = true
    }

    /// Play Next or Play Later.
    func enqueue(_ tracks: [DemoMusicCatalog.Track], at position: UpNextEdit.Position) {
        let entries = tracks.map { Entry(track: $0) }
        let range = UpNextEdit.upcomingRange(count: queue.count, current: index)
        queue.replaceSubrange(range, with: UpNextEdit.inserted(entries, into: Array(queue[range]), at: position))
    }

    // MARK: QueueEditing

    func moveUpNext(from offsets: IndexSet, to destination: Int) async {
        editUpcoming { UpNextEdit.moved($0, from: offsets, to: destination) }
    }

    func removeUpNext(at offsets: IndexSet) async {
        editUpcoming { UpNextEdit.removed($0, at: offsets) }
    }

    func clearUpNext() async {
        editUpcoming { _ in [] }
    }

    func setShuffle(_ isOn: Bool) {
        shuffle = isOn
        guard isOn else { return }
        editUpcoming { $0.shuffled() }
    }

    func setRepeat(_ mode: MusicRepeatMode) {
        repeatMode = mode
    }

    private func editUpcoming(_ change: ([Entry]) -> [Entry]) {
        let range = UpNextEdit.upcomingRange(count: queue.count, current: index)
        queue.replaceSubrange(range, with: change(Array(queue[range])))
    }
}
