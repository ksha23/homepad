import Foundation
import HomePadCore
import MusicKit

/// The saved place: where playback was, so a restart continues the same song at
/// the same moment, and the station that carries on after a resumed station song.
extension AppleMusicPlayer {
    /// Loads the saved place and shows it as Now Playing. Called once at launch.
    func loadResumePoint(settings: SettingsStore) {
        self.settings = settings
        resumePoint = settings[AudioSettings.appleMusicResume]
        // Nothing is queued at launch: MusicKit's queue does not outlive HomePad.
        if let resumePoint {
            nowPlaying = Self.preview(resumePoint)
            currentArtwork = resumePoint.artwork
        }
    }

    /// Takes on a person's saved place at launch when the iPad's own
    /// (`appleMusicResume`) has none, so their place is shown, not lost.
    func adoptResumePoint(_ point: MusicResumePoint) {
        resumePoint = point
        nowPlaying = Self.preview(point)
        currentArtwork = point.artwork
    }

    /// Writes where playback is, when the song changed, play and pause changed,
    /// or 10 seconds passed. Cheap: one small JSON value in the iPad's settings.
    func saveResumePoint(_ entry: ApplicationMusicPlayer.Queue.Entry, artwork: Artwork?, index: Int?, item: NowPlaying) {
        guard let settings, let container else { return }
        var songID: String?
        if case .song(let song) = entry.item { songID = song.id.rawValue }
        let point = MusicResumePoint(
            container: container, songID: songID, title: item.title, artist: item.artist, album: item.album,
            artwork: artwork, duration: item.duration, index: index, position: item.elapsed ?? 0, savedAt: Date()
        )
        // A pause saves the exact moment at once.
        let pausedElsewhere = !item.isPlaying && abs((resumePoint?.position ?? -1) - point.position) > 0.5
        guard MusicResumePoint.needsSaving(point, after: resumePoint) || pausedElsewhere else { return }
        resumePoint = point
        settings[AudioSettings.appleMusicResume] = point
    }

    /// The position part of `saveResumePoint`, from the progress task.
    func saveCurrentPosition() {
        guard let settings, var point = resumePoint else { return }
        let position = ApplicationMusicPlayer.shared.playbackTime
        guard abs(position - point.position) >= 10 else { return }
        point.position = position
        point.savedAt = Date()
        resumePoint = point
        settings[AudioSettings.appleMusicResume] = point
    }

    /// Moves a saved place's position, while it is shown paused and not loaded, so play continues there.
    func moveSavedPlace(_ point: MusicResumePoint, to seconds: TimeInterval) {
        var point = point
        point.position = min(max(0, seconds), point.duration ?? seconds)
        point.savedAt = Date()
        AppleMusicTrace.note("seek moved the saved place to \(Int(point.position)) s")
        resumePoint = point
        settings?[AudioSettings.appleMusicResume] = point
        nowPlaying = Self.preview(point)
    }

    /// Rebuilds the saved queue and continues the saved song where it stopped.
    func restore(_ point: MusicResumePoint) async throws {
        try await prepare(point)
        try await ApplicationMusicPlayer.shared.play()
        observePlayer()
        refresh()
    }

    /// Everything `restore` does before it plays: the saved queue is loaded,
    /// at the saved song and moment, and stays paused.
    func prepare(_ point: MusicResumePoint) async throws {
        guard await requestAuthorization() else { throw AudioError.musicNotAuthorized }
        container = point.container
        let player = ApplicationMusicPlayer.shared
        shownEntryID = nil
        coverHold.reset()
        if case .station(let id) = point.container {
            try await restoreStation(MusicItemID(id), point: point)
        } else {
            let (queue, foundSong) = try await Self.queue(for: point)
            AppleMusicTrace.note("restore \(point.container.kind) song=\(point.songID ?? "none") found=\(foundSong) at \(Int(point.position))s")
            player.queue = queue
            try await player.prepareToPlay()
            if foundSong {
                player.playbackTime = MusicResumePoint.resumePosition(point.position, duration: point.duration)
            }
        }
    }

    /// A station picks its own songs: restarting it played another song than the
    /// one shown, and MusicKit ignores songs queued with a station (ahead of it
    /// in one queue it played the station's next song, and Play Next was skipped
    /// past). So the saved song plays on its own from where it stopped, and the
    /// station starts when it ends (`continueStationIfSongEnded`).
    private func restoreStation(_ id: MusicItemID, point: MusicResumePoint) async throws {
        let player = ApplicationMusicPlayer.shared
        let station = try await AppleMusicLookup.station(id, title: point.title)
        guard let songID = point.songID,
              let song = try? await MusicCatalogResourceRequest<Song>(matching: \.id, equalTo: MusicItemID(songID)).response().items.first
        else {
            AppleMusicTrace.note("restore station: saved song \(point.songID ?? "none") not found, station alone")
            player.queue = [station]
            try await player.prepareToPlay()
            return
        }
        AppleMusicTrace.note("restore station: song \(songID) alone at \(Int(point.position))s, then the station")
        player.queue = [song]
        try await player.prepareToPlay()
        player.playbackTime = MusicResumePoint.resumePosition(point.position, duration: point.duration)
        stationAfterSong = StationAfterSong(station: station, duration: song.duration ?? point.duration)
    }

    /// Starts the station once the song resumed ahead of it has played to its end.
    /// Called on every player change, before Now Playing takes the new position.
    func continueStationIfSongEnded() {
        guard let pending = stationAfterSong else { return }
        let player = ApplicationMusicPlayer.shared
        let status = player.state.playbackStatus
        if status == .playing, player.queue.currentEntry != nil {
            stationAfterSong?.hasPlayed = true
            return
        }
        // The last position seen while playing, at most a second old.
        let lastPosition = nowPlaying?.elapsed ?? 0
        let reachedEnd = pending.duration.map { lastPosition >= $0 - 2.5 } ?? false
        guard pending.hasPlayed, player.queue.currentEntry == nil || status == .stopped || reachedEnd else { return }
        startStationAfterSong()
    }

    func startStationAfterSong() {
        guard let pending = stationAfterSong else { return }
        stationAfterSong = nil
        AppleMusicTrace.note("resumed song done, station \(pending.station.id.rawValue) carries on")
        Task {
            let player = ApplicationMusicPlayer.shared
            shownEntryID = nil
            coverHold.reset()
            player.queue = [pending.station]
            try? await player.play()
            refresh()
        }
    }

    /// The saved queue, starting at the saved song. `foundSong` is false when the
    /// queue starts elsewhere (a station, or the song is gone), so no seek.
    private static func queue(for point: MusicResumePoint) async throws -> (ApplicationMusicPlayer.Queue, foundSong: Bool) {
        switch point.container {
        case .album(let id):
            guard let album = try await AppleMusicLookup.album(MusicItemID(id)) else { throw AudioError.nothingFound(point.album ?? point.title) }
            let full = try await album.with([.tracks])
            let tracks = Array(full.tracks ?? [])
            guard !tracks.isEmpty else { return (ApplicationMusicPlayer.Queue(for: [album]), false) }
            let start = MusicResumePoint.startIndex(songIDs: tracks.map(\.id.rawValue), songID: point.songID, savedIndex: point.index)
            return (ApplicationMusicPlayer.Queue(album: full, startingAt: tracks[start]), tracks[start].id.rawValue == point.songID)
        case .playlist(let id):
            guard let playlist = try await AppleMusicLookup.playlist(MusicItemID(id)) else { throw AudioError.nothingFound(point.title) }
            let full = try await playlist.with([.entries])
            let entries = Array(full.entries ?? [])
            guard !entries.isEmpty else { return (ApplicationMusicPlayer.Queue(for: [playlist]), false) }
            let ids = entries.map { $0.item?.id.rawValue ?? $0.id.rawValue }
            let start = MusicResumePoint.startIndex(songIDs: ids, songID: point.songID, savedIndex: point.index)
            return (ApplicationMusicPlayer.Queue(playlist: full, startingAt: entries[start]), ids[start] == point.songID)
        case .station(let id):
            // `restoreStation` resumes stations at the saved song.
            return (ApplicationMusicPlayer.Queue(for: [try await AppleMusicLookup.station(MusicItemID(id), title: point.title)]), false)
        case .songs(let ids):
            let found = try await AppleMusicLookup.songs(ids)
            let songs = ids.compactMap { id in found.first { $0.id.rawValue == id } }
            guard !songs.isEmpty else { throw AudioError.nothingFound(point.title) }
            let start = MusicResumePoint.startIndex(songIDs: songs.map(\.id.rawValue), songID: point.songID, savedIndex: point.index)
            return (ApplicationMusicPlayer.Queue(for: songs, startingAt: songs[start]), songs[start].id.rawValue == point.songID)
        }
    }

    /// What a queue built from `items` is, for the resume point. Nil for anything
    /// it cannot rebuild, which then simply is not saved.
    static func container(for items: [any PlayableMusicItem]) -> MusicResumePoint.Container? {
        if items.count == 1, let item = items.first {
            switch item {
            case let album as Album: return .album(album.id.rawValue)
            case let playlist as Playlist: return .playlist(playlist.id.rawValue)
            case let station as Station: return .station(station.id.rawValue)
            default: break
            }
        }
        let songs = items.compactMap { $0 as? Song }
        return songs.count == items.count && !songs.isEmpty ? .songs(songs.map(\.id.rawValue)) : nil
    }

    /// The saved song as Now Playing, paused at where it stopped.
    static func preview(_ point: MusicResumePoint) -> NowPlaying {
        NowPlaying(
            title: point.title, artist: point.artist, album: point.album,
            artworkURL: point.artwork?.url(width: 1200, height: 1200),
            duration: point.duration, elapsed: point.position, isPlaying: false, source: .appleMusic
        )
    }
}
