import Foundation
import MusicKit

/// Up Next: Play Next and Play Later, moving, removing and clearing songs,
/// shuffle and repeat, and each person's saved queue.
///
/// MusicKit limits learned on a device:
/// - `ApplicationMusicPlayer` ignores songs queued together with a station
///   (ahead of it the station's next song played, and Play Next was skipped
///   past). So a station's queue cannot be edited or added to, and the song
///   resumed ahead of a station (`stationAfterSong`) counts as the station.
/// - The player's queue does not outlive HomePad, so a saved queue is rebuilt
///   from song IDs (`MusicResumePoint`) when it plays again.
extension AppleMusicPlayer: QueueEditing {
    /// How many upcoming songs Up Next lists.
    static let upNextLength = 100

    var queueAbilities: QueueAbilities {
        if isStationQueue { return [] }
        if holdsSavedPlace { return resumePoint == nil ? [.add] : .all }
        if ApplicationMusicPlayer.shared.queue.currentEntry == nil && resumePoint == nil { return [.add] }
        return .all
    }

    /// A station picks its own songs, and a song resumed ahead of one is part of it.
    var isStationQueue: Bool {
        if stationAfterSong != nil { return true }
        if case .station = container { return true }
        return false
    }

    var queueOrigin: String? {
        originTitle.map { "Playing from \($0)" }
    }

    // MARK: Adding

    /// Play Next (after the current song) or Play Later (at the end). With
    /// nothing queued it plays at once, as in the Music app.
    func enqueue(_ items: [any PlayableMusicItem], at position: UpNextEdit.Position) async throws {
        guard !items.isEmpty, !isStationQueue else { return }
        if holdsSavedPlace { await loadHeldQueue() }
        let player = ApplicationMusicPlayer.shared
        guard !holdsSavedPlace, player.queue.currentEntry != nil else {
            try await play(mixed: items)
            return
        }
        let entries = items.map { MusicPlayer.Queue.Entry($0) }
        try await player.queue.insert(entries, position: position == .next ? .afterCurrentEntry : .tail)
        queueEdited = true
        AppleMusicTrace.note("enqueue \(items.count) \(position)")
        observePlayer()
        refresh()
    }

    // MARK: Editing

    func moveUpNext(from offsets: IndexSet, to destination: Int) async {
        await editUpcoming { UpNextEdit.moved($0, from: offsets, to: destination) }
    }

    func removeUpNext(at offsets: IndexSet) async {
        await editUpcoming { UpNextEdit.removed($0, at: offsets) }
    }

    func clearUpNext() async {
        await editUpcoming { _ in [] }
    }

    /// Changes only the entries after the current one, so the song that plays is never touched.
    private func editUpcoming(_ change: ([MusicPlayer.Queue.Entry]) -> [MusicPlayer.Queue.Entry]) async {
        guard !isStationQueue else { return }
        if holdsSavedPlace { await loadHeldQueue() }
        guard !holdsSavedPlace else { return }
        let player = ApplicationMusicPlayer.shared
        var entries = player.queue.entries
        let current = player.queue.currentEntry.flatMap { entry in entries.firstIndex { $0.id == entry.id } }
        let range = UpNextEdit.upcomingRange(count: entries.count, current: current)
        let shown = range.prefix(Self.upNextLength)
        // Edits count from the first upcoming song, within what Up Next lists.
        let edited = change(Array(entries[shown.startIndex..<shown.endIndex]))
        entries.replaceSubrange(shown.startIndex..<shown.endIndex, with: edited)
        player.queue.entries = entries
        queueEdited = true
        AppleMusicTrace.note("edit up next: \(edited.count) of \(range.count) shown")
        refresh()
    }

    // MARK: Shuffle and repeat

    func setShuffle(_ isOn: Bool) {
        guard !isStationQueue else { return }
        shuffle = isOn
        if hasLiveQueue { ApplicationMusicPlayer.shared.state.shuffleMode = isOn ? .songs : .off }
        refresh()
    }

    func setRepeat(_ mode: MusicRepeatMode) {
        guard !isStationQueue else { return }
        repeatMode = mode
        if hasLiveQueue { ApplicationMusicPlayer.shared.state.repeatMode = Self.musicKitRepeat(mode) }
        refresh()
    }

    /// Reads shuffle and repeat from the player, which can change them itself.
    func readPlaybackModes(_ state: MusicPlayer.State) {
        if let mode = state.shuffleMode {
            let isOn = mode == .songs
            if shuffle != isOn { shuffle = isOn }
        }
        if let mode = state.repeatMode {
            let value: MusicRepeatMode = switch mode {
            case .one: .one
            case .all: .all
            default: .off
            }
            if repeatMode != value { repeatMode = value }
        }
    }

    private var hasLiveQueue: Bool {
        !holdsSavedPlace && ApplicationMusicPlayer.shared.queue.currentEntry != nil
    }

    static func musicKitRepeat(_ mode: MusicRepeatMode) -> MusicPlayer.RepeatMode {
        switch mode {
        case .off: .none
        case .all: .all
        case .one: .one
        }
    }

    // MARK: A person's saved queue

    /// Shows another person's saved place, paused, without playing. MusicKit
    /// keeps the previous person's queue loaded but stopped, and Now Playing
    /// ignores it until Play restores the saved one (`resume`).
    func holdSavedPlace(_ state: MemberMusicState) {
        let player = ApplicationMusicPlayer.shared
        if player.queue.currentEntry != nil, player.state.playbackStatus != .stopped { player.stop() }
        AppleMusicTrace.note("hold saved place: \(state.resume?.title ?? "nothing")")
        stationAfterSong = nil
        holdsSavedPlace = true
        queueEdited = false
        shownEntryID = nil
        coverHold.reset()
        resumePoint = state.resume
        settings?[AudioSettings.appleMusicResume] = state.resume
        container = state.resume?.container
        loadSavedQueue(state)
        refresh()
    }

    /// Takes on the saved upcoming songs, shuffle, repeat and origin, for Up Next
    /// and Now Playing before playback starts again.
    func loadSavedQueue(_ state: MemberMusicState) {
        savedUpNext = state.upNext.map(\.queueItem)
        shuffle = state.shuffle
        repeatMode = state.repeatMode
        originTitle = state.originTitle
        // At launch nothing is queued yet, so Up Next lists the saved songs.
        if shownEntryID == nil { upNext = savedUpNext }
    }

    /// What to keep for the queue's owner: the place, the next songs, shuffle and repeat.
    func savedQueue(into state: inout MemberMusicState) {
        state.resume = resumePoint
        state.upNext = Array(upNext.prefix(MemberMusicState.upNextLimit)).map(SavedQueueItem.init)
        state.shuffle = shuffle
        state.repeatMode = repeatMode
        state.originTitle = originTitle
    }

    /// Continues a saved place: the queue is rebuilt and plays from the saved moment,
    /// with the saved shuffle and repeat.
    func restoreSavedPlace(_ point: MusicResumePoint) async throws {
        let wasHeld = holdsSavedPlace
        holdsSavedPlace = false
        do {
            try await restore(point)
        } catch {
            holdsSavedPlace = wasHeld
            throw error
        }
        applySavedModes()
    }

    /// Loads a held saved place into the player, paused, so Up Next can be changed before it plays.
    @discardableResult
    func loadHeldQueue() async -> Bool {
        guard holdsSavedPlace else { return true }
        guard let point = resumePoint, !isStationQueue else { return false }
        holdsSavedPlace = false
        do {
            try await prepare(point)
            applySavedModes()
            observePlayer()
            refresh()
            return true
        } catch {
            AppleMusicTrace.note("load held queue failed: \(error)")
            holdsSavedPlace = true
            return false
        }
    }

    private func applySavedModes() {
        guard !isStationQueue else { return }
        let state = ApplicationMusicPlayer.shared.state
        state.shuffleMode = shuffle ? .songs : .off
        state.repeatMode = Self.musicKitRepeat(repeatMode)
    }

    // MARK: Up Next rows

    /// Rebuilds Up Next only when the upcoming entries changed, since the player
    /// announces changes often and each row reads its cover.
    func updateUpNext(_ upcoming: [MusicPlayer.Queue.Entry]) {
        let rows = upcoming.map { entry in
            let artwork = Self.realArtwork(of: entry)
            return QueueItem(id: entry.id, title: entry.title, subtitle: entry.subtitle,
                             artworkURL: artwork?.url(width: 200, height: 200), artwork: artwork, songID: Self.songID(of: entry))
        }
        if rows != upNext { upNext = rows }
    }

    static func songID(of entry: MusicPlayer.Queue.Entry) -> String? {
        if case .song(let song) = entry.item { return song.id.rawValue }
        return nil
    }

    /// An edited queue as its songs from the current one on, at most 150, so it can be rebuilt.
    static func editedContainer(_ entries: [MusicPlayer.Queue.Entry], current: Int?) -> MusicResumePoint.Container? {
        let ids = entries.dropFirst(current ?? 0).compactMap(songID).prefix(150)
        return ids.isEmpty ? nil : .songs(Array(ids))
    }

    /// "Night Signals" for an album, playlist or station, nil for a list of songs.
    static func originTitle(of items: [any PlayableMusicItem]) -> String? {
        guard items.count == 1, let item = items.first else { return nil }
        switch item {
        case let album as Album: return album.title
        case let playlist as Playlist: return playlist.name
        case let station as Station: return station.name
        default: return nil
        }
    }

    // MARK: Saving

    /// Tells the owner when something worth saving changed: the song, play or
    /// pause, Up Next, shuffle or repeat. Not the position, which `saveResumePoint` keeps.
    func notifyIfQueueChanged() {
        let signature = QueueSignature(entryID: shownEntryID, title: nowPlaying?.title, isPlaying: nowPlaying?.isPlaying == true,
                                       upNext: upNext.map(\.id), shuffle: shuffle, repeatMode: repeatMode)
        guard signature != lastQueueSignature else { return }
        lastQueueSignature = signature
        onQueueChange?()
    }
}

/// What `notifyIfQueueChanged` compares.
struct QueueSignature: Equatable {
    var entryID: String?
    var title: String?
    var isPlaying: Bool
    var upNext: [String]
    var shuffle: Bool
    var repeatMode: MusicRepeatMode
}
