import Foundation
import HomePadCore

/// How the demo speakers change: queues, transport, volume and multi-room groups.
/// A group leader's media is copied to its members, as Music Assistant reports it.
extension DemoMusicAssistantHome {
    static func speaker(_ object: String, _ name: String, room: String, model: String, volume: Double) -> HomeAccessory {
        HomeAccessory(
            id: "ha:media_player.\(object)", name: name, room: room, kind: .mediaPlayer, backend: .homeAssistant,
            capabilities: [.power, .playback, .volume],
            state: AccessoryState(isOn: true, volume: volume, isPlaying: false),
            integration: MusicAssistantPlayer.integration, deviceClass: "speaker", deviceModel: model
        )
    }

    /// Loads a queue on a speaker and plays its first song.
    func start(_ tracks: [DemoMusicCatalog.Track], on id: String, position: TimeInterval = 0) {
        guard !tracks.isEmpty else { return }
        queues[id] = (tracks, 0)
        show(tracks[0], on: id, position: position)
    }

    func playRadio(_ station: MAMediaItem, on id: String) {
        queues[id] = nil
        update(id) { state in
            state.mediaTitle = station.name
            state.mediaArtist = "Live radio"
            state.mediaAlbum = nil
            state.mediaDuration = nil
            state.mediaPosition = nil
            state.isPlaying = true
        }
    }

    func step(_ id: String, by offset: Int) {
        guard let queue = queues[id] else { return }
        let index = max(0, min(queue.tracks.count - 1, queue.index + offset))
        queues[id] = (queue.tracks, index)
        show(queue.tracks[index], on: id, position: 0)
    }

    func pause(_ id: String) {
        update(id) { state in
            state.mediaPosition = RemotePlayerController.elapsed(state, isPlaying: state.isPlaying ?? false)
            state.mediaPositionUpdatedAt = Date()
            state.isPlaying = false
        }
    }

    func clear(_ id: String) {
        queues[id] = nil
        update(id) { state in
            state.mediaTitle = nil
            state.mediaArtist = nil
            state.mediaAlbum = nil
            state.mediaDuration = nil
            state.mediaPosition = nil
            state.isPlaying = false
        }
    }

    /// `media_player.join`: members follow the leader and take on what it plays.
    func join(_ leader: String, members: [String]) {
        let group = [leader] + members.filter { $0 != leader }
        for id in group {
            unjoin(id, keepingMedia: true)
            set(id) { $0.mediaGroupMemberIDs = group }
        }
        update(leader) { _ in }
    }

    func unjoin(_ id: String, keepingMedia: Bool = false) {
        guard let members = state(of: id)?.mediaGroupMemberIDs else { return }
        let remaining = members.filter { $0 != id }
        for member in remaining { set(member) { $0.mediaGroupMemberIDs = remaining.count > 1 ? remaining : nil } }
        set(id) { $0.mediaGroupMemberIDs = nil }
        if !keepingMedia, members.first != id { clear(id) }
    }

    /// Changes a speaker, then copies its media to the speakers that follow it.
    func update(_ id: String, _ change: (inout AccessoryState) -> Void) {
        set(id, change)
        guard let leader = state(of: id), let members = leader.mediaGroupMemberIDs, members.first == id else { return }
        for member in members.dropFirst() {
            set(member) { state in
                state.mediaTitle = leader.mediaTitle
                state.mediaArtist = leader.mediaArtist
                state.mediaAlbum = leader.mediaAlbum
                state.mediaDuration = leader.mediaDuration
                state.mediaPosition = leader.mediaPosition
                state.mediaPositionUpdatedAt = leader.mediaPositionUpdatedAt
                state.isPlaying = leader.isPlaying
            }
        }
    }

    private func show(_ track: DemoMusicCatalog.Track, on id: String, position: TimeInterval) {
        update(id) { state in
            state.mediaTitle = track.title
            state.mediaArtist = track.artist
            state.mediaAlbum = track.album
            state.mediaDuration = track.duration
            state.mediaPosition = position
            state.mediaPositionUpdatedAt = Date()
            state.isPlaying = true
        }
    }

    private func state(of id: String) -> AccessoryState? {
        accessories.first { $0.id == id }?.state
    }

    private func set(_ id: String, _ change: (inout AccessoryState) -> Void) {
        guard let index = accessories.firstIndex(where: { $0.id == id }) else { return }
        change(&accessories[index].state)
    }
}
