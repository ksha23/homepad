import Foundation
import HomePadCore

/// Up Next, Play Next and Play Later, shuffle and repeat, for what is in focus.
/// This iPad's queue can be edited. A Music Assistant speaker's queue takes
/// Play Next and Play Later through `play_media`'s `enqueue`.
extension AudioMediaService {
    /// The local queue that Up Next and the shuffle and repeat buttons change,
    /// while this iPad's music is in focus.
    var editableQueue: (any QueueEditing)? {
        guard transportTarget == .local else { return nil }
        return activeSource as? any QueueEditing
    }

    /// What the queue in focus allows. Spotify's can shuffle and repeat, and is
    /// added to from its tiles, but the Web API cannot reorder it.
    var queueAbilities: QueueAbilities {
        if transportTarget == .spotify { return spotify.playback == nil ? [] : [.shuffle, .repeat] }
        return editableQueue?.queueAbilities ?? []
    }

    var isShuffled: Bool {
        transportTarget == .spotify ? spotify.playback?.isShuffled == true : editableQueue?.shuffle ?? false
    }

    var repeatMode: MusicRepeatMode {
        transportTarget == .spotify ? spotify.playback?.repeatMode ?? .off : editableQueue?.repeatMode ?? .off
    }

    /// "Playing from Night Signals", when the queue came from one album, playlist or station.
    var queueOrigin: String? { editableQueue?.queueOrigin }

    func toggleShuffle() {
        if transportTarget == .spotify {
            let isOn = !isShuffled
            Task { await spotifyPerform { try await $0.setShuffle(isOn) } }
            return
        }
        guard let queue = editableQueue else { return }
        queue.setShuffle(!queue.shuffle)
    }

    func cycleRepeat() {
        if transportTarget == .spotify {
            let mode = repeatMode.next
            Task { await spotifyPerform { try await $0.setRepeat(mode) } }
            return
        }
        guard let queue = editableQueue else { return }
        queue.setRepeat(queue.repeatMode.next)
    }

    func moveUpNext(from offsets: IndexSet, to destination: Int) async {
        await editableQueue?.moveUpNext(from: offsets, to: destination)
    }

    func removeUpNext(at offsets: IndexSet) async {
        await editableQueue?.removeUpNext(at: offsets)
    }

    func clearUpNext() async {
        await editableQueue?.clearUpNext()
    }

    // MARK: Play Next and Play Later

    /// False while a station plays here: MusicKit ignores songs queued with a station.
    var canQueueAppleMusic: Bool {
        !(activeKind == .appleMusic && appleMusic.isStationQueue)
    }

    /// Play Next or Play Later for the simulator's demo queue.
    func enqueueDemo(matching text: String, at position: UpNextEdit.Position) {
        guard let demo else { return }
        guard activeKind == .demo else { return playDemo(matching: text) }
        demo.enqueue(DemoMusicCatalog.tracksToQueue(text), at: position)
    }

    /// Play Next or Play Later on the chosen Music Assistant speaker.
    func enqueue(_ item: MAMediaItem, at position: UpNextEdit.Position) async {
        await perform { try await musicAssistant.play(item, enqueue: position == .next ? .next : .add) }
    }
}
