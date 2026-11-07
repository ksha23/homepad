import Combine
import Foundation
import HomePadCore
import MusicKit
import Observation

/// Apple Music playback through MusicKit's `ApplicationMusicPlayer`.
///
/// Why `ApplicationMusicPlayer` and not `SystemMusicPlayer`:
/// - It runs its own audio session and its own long-form AirPlay route, apart
///   from HomePad's. It plays to the HomePods picked in AirPlay, several at once,
///   while HomePad keeps the microphone on, so HomePad claims no session for it
///   (`AudioMediaService.prepareToPlay`). `MusicAirPlayVolume` sets the volume
///   of those speakers.
/// - HomePad's queue never disturbs the Music app's own queue on this iPad.
/// - HomePad gets full queue control (insert, reorder, transitions on iOS 18+).
/// The trade-offs: playback stops if HomePad is terminated, the Music app does
/// not show HomePad's queue, and some library-only content behaves like it does
/// in third-party apps rather than in the Music app. `SystemMusicPlayer` would
/// instead drive the Music app's player, which survives HomePad quitting but
/// takes over the Music app's queue.
///
/// Covers live in `AppleMusicPlayer+Covers.swift`. The saved place and the
/// station that follows a resumed song live in `AppleMusicPlayer+Resume.swift`.
@MainActor
@Observable
final class AppleMusicPlayer: PlaybackSource {
    let kind = MediaSourceKind.appleMusic
    private(set) var authorization: MusicAuthorization.Status = MusicAuthorization.currentStatus
    private(set) var canPlayCatalog = false
    /// The songs after the current one, as Up Next lists them (`AppleMusicPlayer+Queue.swift`).
    var upNext: [QueueItem] = []
    /// MusicKit artwork for the current entry. Library artwork only renders through `ArtworkImage`.
    var currentArtwork: Artwork?
    /// The next queue entry's artwork. Now Playing draws it invisibly ahead of
    /// time, so the next cover is already loaded when the track changes.
    private(set) var nextArtwork: Artwork?
    /// Where playback was saved last, shown as Now Playing until it plays again.
    /// Written by the resume code.
    var resumePoint: MusicResumePoint?
    /// Shuffle and repeat, read from the player while a queue is loaded and kept
    /// for the saved place otherwise (`AppleMusicPlayer+Queue.swift`).
    var shuffle = false
    var repeatMode: MusicRepeatMode = .off
    /// "Night Signals" for a queue built from that album, for "Playing from".
    var originTitle: String?
    /// The saved place's upcoming songs, shown in Up Next until playback starts again.
    var savedUpNext: [QueueItem] = []
    /// True while Now Playing shows a person's saved place instead of what
    /// MusicKit still has loaded (another person's paused queue). Play restores it.
    @ObservationIgnored var holdsSavedPlace = false
    /// True once Up Next was changed, so the saved place keeps the edited song list
    /// rather than the album or playlist it started from.
    @ObservationIgnored var queueEdited = false
    /// Told when the song, play and pause, Up Next, shuffle or repeat change, so the owner's state is saved.
    @ObservationIgnored var onQueueChange: (() -> Void)?
    @ObservationIgnored var lastQueueSignature: QueueSignature?

    /// What plays, for every Now Playing surface. The resume code writes it too.
    ///
    /// Observers hear about every change except the progress task's: it moves
    /// `elapsed` on once a second without telling them (`trackProgress`). A
    /// notification each second redrew every view that reads Now Playing (the
    /// pill on every screen, Handoff, Control Center, widgets, the Music app)
    /// while only the scrubber shows the time, and the scrubber reads it on its
    /// own one second timeline. Anyone who reads still gets the current `elapsed`.
    var nowPlaying: NowPlaying? {
        get {
            access(keyPath: \.nowPlaying)
            return shown
        }
        set {
            guard newValue != shown else { return }
            withMutation(keyPath: \.nowPlaying) { shown = newValue }
        }
    }

    @ObservationIgnored private var shown: NowPlaying?
    @ObservationIgnored private var subscriptions = Set<AnyCancellable>()
    @ObservationIgnored private var progressTask: Task<Void, Never>?
    /// The queue entry `nowPlaying` shows.
    @ObservationIgnored var shownEntryID: String?
    @ObservationIgnored var coverHold = CoverHold<Artwork>()
    /// Real covers fetched from the catalog for songs MusicKit gave a stand-in.
    @ObservationIgnored var catalogCovers: [MusicItemID: Artwork] = [:]
    @ObservationIgnored var catalogRequests: Set<MusicItemID> = []
    /// True while the current song shows a stand-in, so `pollForCover` asks again.
    @ObservationIgnored var isWaitingForCover = false
    @ObservationIgnored var coverPollTask: Task<Void, Never>?
    /// What the current queue was built from, for the resume point.
    @ObservationIgnored var container: MusicResumePoint.Container?
    /// The station to start when the song resumed ahead of it ends.
    @ObservationIgnored var stationAfterSong: StationAfterSong?
    @ObservationIgnored var settings: SettingsStore?

    struct StationAfterSong {
        let station: Station
        let duration: TimeInterval?
        /// The song played after the restore, so a paused, unplayed song never ends early.
        var hasPlayed = false
    }

    var isAuthorized: Bool { authorization == .authorized }
    var capabilities: PlaybackCapabilities { .track }

    // MARK: Authorization

    /// Asks for Apple Music access the first time, then checks the subscription.
    @discardableResult
    func requestAuthorization() async -> Bool {
        if authorization == .notDetermined {
            authorization = await MusicAuthorization.request()
        }
        if isAuthorized { await refreshSubscription() }
        return isAuthorized
    }

    func refreshSubscription() async {
        guard let subscription = try? await MusicSubscription.current else { return }
        canPlayCatalog = subscription.canPlayCatalogContent
    }

    // MARK: Playing

    /// Plays one album, playlist, station or song. `shuffled` plays it in shuffled order.
    func play<Item: PlayableMusicItem>(_ item: Item, shuffled: Bool = false) async throws {
        try await start(ApplicationMusicPlayer.Queue(for: [item]), items: [item], shuffled: shuffled)
    }

    func play<Item: PlayableMusicItem>(_ items: [Item], startingAt first: Item? = nil, shuffled: Bool = false) async throws {
        try await start(ApplicationMusicPlayer.Queue(for: items, startingAt: first), items: items, shuffled: shuffled)
    }

    /// Plays an album from one of its tracks.
    func play(_ album: Album, startingAt track: Track) async throws {
        try await start(ApplicationMusicPlayer.Queue(album: album, startingAt: track), items: [album], shuffled: false)
    }

    /// Plays a playlist from one of its songs.
    func play(_ playlist: Playlist, startingAt entry: Playlist.Entry) async throws {
        try await start(ApplicationMusicPlayer.Queue(playlist: playlist, startingAt: entry), items: [playlist], shuffled: false)
    }

    /// Plays items of different kinds in order, such as Play Next with nothing queued.
    func play(mixed items: [any PlayableMusicItem]) async throws {
        try await start(ApplicationMusicPlayer.Queue(items.map { MusicPlayer.Queue.Entry($0) }), items: items, shuffled: false)
    }

    /// Starts a new queue. Like the Music app, Play plays in order and Shuffle shuffles.
    private func start(_ queue: ApplicationMusicPlayer.Queue, items: [any PlayableMusicItem], shuffled: Bool) async throws {
        container = Self.container(for: items)
        originTitle = Self.originTitle(of: items)
        guard await requestAuthorization() else { throw AudioError.musicNotAuthorized }
        let player = ApplicationMusicPlayer.shared
        stationAfterSong = nil
        shownEntryID = nil
        coverHold.reset()
        holdsSavedPlace = false
        queueEdited = false
        savedUpNext = []
        player.queue = queue
        player.state.shuffleMode = shuffled ? .songs : .off
        try await player.play()
        observePlayer()
        refresh()
    }

    /// Plays on, or after a restart (or a switch to another person's queue)
    /// continues the saved song where it stopped.
    func resume() async throws {
        if holdsSavedPlace || ApplicationMusicPlayer.shared.queue.currentEntry == nil, let resumePoint {
            try await restoreSavedPlace(resumePoint)
            return
        }
        // A person with nothing saved: the loaded queue is someone else's.
        guard !holdsSavedPlace else { return }
        try await ApplicationMusicPlayer.shared.play()
        refresh()
    }

    func pause() {
        guard nowPlaying != nil else { return }
        ApplicationMusicPlayer.shared.pause()
        refresh()
    }

    func stop() {
        guard nowPlaying != nil else { return }
        stationAfterSong = nil
        ApplicationMusicPlayer.shared.stop()
        nowPlaying = nil
        upNext = []
        currentArtwork = nil
        nextArtwork = nil
        shownEntryID = nil
        coverHold.reset()
        progressTask?.cancel()
        progressTask = nil
    }

    func skipForward() async {
        guard !holdsSavedPlace else { return }
        AppleMusicTrace.note("skip forward")
        // The song resumed ahead of its station is alone in the queue: Next is the station.
        if stationAfterSong != nil {
            startStationAfterSong()
            return
        }
        try? await ApplicationMusicPlayer.shared.skipToNextEntry()
        refreshAfterSkip()
    }

    /// Restarts the song when more than a few seconds in, like the Music app.
    func skipBackward() async {
        guard !holdsSavedPlace else { return }
        let player = ApplicationMusicPlayer.shared
        if player.playbackTime > 3 {
            AppleMusicTrace.note("skip back: restart")
            player.restartCurrentEntry()
        } else {
            AppleMusicTrace.note("skip back: previous")
            do { try await player.skipToPreviousEntry() } catch { AppleMusicTrace.note("skip back failed: \(error)") }
        }
        refreshAfterSkip()
    }

    /// MusicKit sets the new song a moment after a skip returns, and its notice
    /// of the change can come before it, so the song is read again shortly
    /// after. Without this, Next right after a restart left the old song shown
    /// while the next one played.
    private func refreshAfterSkip() {
        refresh()
        Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(400))
            self?.refresh()
        }
    }

    func seek(to seconds: TimeInterval) {
        // Showing a person's saved place, nothing of theirs is loaded in MusicKit yet, so the saved
        // place moves instead and play starts there. Seeks here were dropped, and dragging the
        // companion's scrubber over a saved song did nothing.
        if holdsSavedPlace || ApplicationMusicPlayer.shared.queue.currentEntry == nil, let resumePoint {
            moveSavedPlace(resumePoint, to: seconds)
            return
        }
        // Held with nothing saved: what MusicKit has loaded is someone else's, so it stays put.
        guard !holdsSavedPlace else { return }
        let player = ApplicationMusicPlayer.shared
        AppleMusicTrace.note("seek to \(Self.seconds(seconds)) from \(Self.seconds(player.playbackTime)) on \(player.state.playbackStatus)")
        player.playbackTime = max(0, seconds)
        refresh()
    }

    private static func seconds(_ value: TimeInterval) -> String { String(format: "%.2f", value) }

    /// `ApplicationMusicPlayer` has no volume of its own, so the sleep timer pauses it at the end instead.
    func setFadeLevel(_ level: Double) {}

    // MARK: State

    /// Follows the player's state and queue. Called once a queue plays.
    func observePlayer() {
        guard subscriptions.isEmpty else { return }
        let player = ApplicationMusicPlayer.shared
        player.state.objectWillChange
            .merge(with: player.queue.objectWillChange)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in MainActor.assumeIsolated { self?.refresh() } }
            .store(in: &subscriptions)
    }

    /// Reads the player into `nowPlaying`, the covers and Up Next, and saves the place.
    func refresh() {
        let player = ApplicationMusicPlayer.shared
        AppleMusicTrace.player(player)
        continueStationIfSongEnded()
        guard !holdsSavedPlace, let entry = player.queue.currentEntry else {
            // Nothing queued since launch, or another person's saved place: show
            // the saved song, paused, so Now Playing offers to continue it rather
            // than the album's first track or what the last person left loaded.
            nowPlaying = resumePoint.map(Self.preview)
            upNext = savedUpNext
            currentArtwork = resumePoint?.artwork
            if let artwork = resumePoint?.artwork { Self.prefetch(artwork) }
            nextArtwork = nil
            shownEntryID = nil
            notifyIfQueueChanged()
            return
        }
        readPlaybackModes(player.state)
        var artist = entry.subtitle
        var album: String?
        var duration: TimeInterval?
        switch entry.item {
        case .song(let song):
            artist = song.artistName
            album = song.albumTitle
            duration = song.duration
        case .musicVideo(let video):
            artist = video.artistName
            duration = video.duration
        default:
            break
        }
        let isPlaying = player.state.playbackStatus == .playing
        let artwork = cover(for: entry)
        // The player's state and queue announce changes often. Only publish what
        // really changed, so screens never redraw (and the cover never reloads)
        // for nothing.
        let item = NowPlaying(
            title: entry.title, artist: artist, album: album,
            artworkURL: artwork?.url(width: 1200, height: 1200),
            duration: duration, elapsed: player.playbackTime, isPlaying: isPlaying, source: .appleMusic
        )
        if !Self.isSameShown(item, nowPlaying) { nowPlaying = item }
        if currentArtwork != artwork { currentArtwork = artwork }
        if shownEntryID != entry.id {
            shownEntryID = entry.id
            AppleMusicTrace.note("shown title=\(entry.title) cover=\(AppleMusicTrace.name(artwork))")
        }
        let entries = Array(player.queue.entries)
        let currentIndex = entries.firstIndex { $0.id == entry.id }
        // An edited queue is saved as its song list from the current song on.
        if queueEdited, let edited = Self.editedContainer(entries, current: currentIndex) { container = edited }
        saveResumePoint(entry, artwork: artwork, index: queueEdited ? 0 : currentIndex, item: item)
        if let artwork { Self.prefetch(artwork) }
        if let index = currentIndex {
            updateUpNext(Array(entries.dropFirst(index + 1).prefix(Self.upNextLength)))
            let followingEntry = entries.dropFirst(index + 1).first
            let following = followingEntry.flatMap { catalogCover(for: $0) ?? Self.realArtwork(of: $0) }
            if let followingEntry, following == nil, Self.isPlaceholder(followingEntry.artwork) {
                // Fetch the next song's real cover now, so a skip shows it at once.
                requestCatalogCover(for: followingEntry)
            }
            if following != nextArtwork {
                nextArtwork = following
                Self.prefetch(following)
            }
        }
        if isPlaying {
            trackProgress()
        } else {
            progressTask?.cancel()
            progressTask = nil
        }
        notifyIfQueueChanged()
    }

    /// Equal apart from a small drift in `elapsed`, which the progress task keeps current anyway.
    private static func isSameShown(_ lhs: NowPlaying, _ rhs: NowPlaying?) -> Bool {
        guard let rhs else { return false }
        var left = lhs
        left.elapsed = rhs.elapsed
        return left == rhs && abs((lhs.elapsed ?? 0) - (rhs.elapsed ?? 0)) < 1.5
    }

    /// Keeps `elapsed` current for the scrubber while playing, and the saved
    /// position close to it (`saveResumePoint` writes every 10 seconds). The
    /// write skips observers (see `nowPlaying`).
    private func trackProgress() {
        guard progressTask == nil else { return }
        progressTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard let self, self.nowPlaying?.isPlaying == true else { return }
                // A song change whose only notice came before it happened left no
                // later one, so the tick catches the shown song up within a second.
                if ApplicationMusicPlayer.shared.queue.currentEntry?.id != self.shownEntryID {
                    AppleMusicTrace.note("caught up with a song change")
                    self.refresh()
                    continue
                }
                self.shown?.elapsed = ApplicationMusicPlayer.shared.playbackTime
                self.saveCurrentPosition()
            }
        }
    }
}
