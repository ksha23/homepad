import Foundation
import HomePadCore

/// Controls speakers that play on their own (HomePods, Sonos, Music Assistant
/// players) through `services.smartHome`, never through Home Assistant directly.
/// Nothing here moves the iPad's own audio.
///
/// Home Assistant players get `media_player.*` service calls. Players from other
/// backends (HomeKit) fall back to plain accessory commands for play, pause and
/// volume. Searching and playing music by name is `MusicAssistantService`'s job.
@MainActor
final class RemotePlayerController {
    private let smartHome: @MainActor () -> any SmartHomeService

    /// - Parameter smartHome: looks the service up at call time, since another module installs it.
    init(smartHome: @escaping @MainActor () -> any SmartHomeService) {
        self.smartHome = smartHome
    }

    var outputs: [AudioOutput] {
        RemotePlayerMapper.outputs(from: smartHome().accessories)
    }

    func accessory(for outputID: AudioOutput.ID) -> HomeAccessory? {
        smartHome().accessory(outputID)
    }

    /// What a remote player reports it is playing.
    func nowPlaying(on outputID: AudioOutput.ID) -> NowPlaying? {
        guard let accessory = accessory(for: outputID), let title = accessory.state.mediaTitle else { return nil }
        let state = accessory.state
        let isPlaying = state.isPlaying ?? state.isOn ?? true
        return NowPlaying(title: title, artist: state.mediaArtist, album: state.mediaAlbum, artworkURL: state.mediaArtworkURL,
                          duration: state.mediaDuration, elapsed: Self.elapsed(state, isPlaying: isPlaying),
                          isPlaying: isPlaying, source: .homeAssistant,
                          outputName: RemotePlayerMapper.displayName(for: accessory))
    }

    /// Extrapolates a remote player's reported position while it plays.
    nonisolated static func elapsed(_ state: AccessoryState, isPlaying: Bool, now: Date = Date()) -> TimeInterval? {
        guard let position = state.mediaPosition else { return nil }
        guard isPlaying, let reportedAt = state.mediaPositionUpdatedAt else { return position }
        let elapsed = position + now.timeIntervalSince(reportedAt)
        return state.mediaDuration.map { min(elapsed, $0) } ?? elapsed
    }

    /// Hands a stream URL (an internet radio station) to the speaker.
    func playStream(_ url: URL, on outputID: AudioOutput.ID) async throws {
        let entity = try homeAssistantEntity(outputID)
        try await send(.playMedia(entityID: entity, contentID: url.absoluteString))
    }

    func setVolume(_ level: Double, on outputID: AudioOutput.ID) async throws {
        if let entity = RemotePlayerMapper.entityID(for: outputID), isHomeAssistant(outputID) {
            try await send(.volumeSet(entityID: entity, level: level))
        } else {
            try await smartHome().perform(.setVolume(max(0, min(1, level))), on: outputID)
        }
    }

    func transport(_ action: MediaServiceCall.Transport, on outputID: AudioOutput.ID) async throws {
        if let entity = RemotePlayerMapper.entityID(for: outputID), isHomeAssistant(outputID) {
            try await send(.transport(entityID: entity, action))
            return
        }
        let command: AccessoryCommand
        switch action {
        case .play: command = .play
        case .pause, .stop: command = .pause
        case .playPause: command = (accessory(for: outputID)?.state.isOn ?? false) ? .pause : .play
        case .next: command = .nextTrack
        case .previous: command = .previousTrack
        }
        try await smartHome().perform(command, on: outputID)
    }

    /// Jumps to a position on a Home Assistant player.
    func seek(to seconds: TimeInterval, on outputID: AudioOutput.ID) async throws {
        try await send(.seek(entityID: try homeAssistantEntity(outputID), to: seconds))
    }

    /// Groups players for multi-room (Sonos, Music Assistant): members follow the leader.
    func group(leader: AudioOutput.ID, members: [AudioOutput.ID]) async throws {
        let leaderEntity = try homeAssistantEntity(leader)
        let memberEntities = try members.map(homeAssistantEntity)
        try await send(.join(leader: leaderEntity, members: memberEntities))
    }

    func ungroup(_ outputID: AudioOutput.ID) async throws {
        try await send(.unjoin(entityID: try homeAssistantEntity(outputID)))
    }

    // MARK: Helpers

    private func isHomeAssistant(_ outputID: AudioOutput.ID) -> Bool {
        accessory(for: outputID)?.backend == .homeAssistant
    }

    private func homeAssistantEntity(_ outputID: AudioOutput.ID) throws -> String {
        guard isHomeAssistant(outputID), let entity = RemotePlayerMapper.entityID(for: outputID) else {
            throw SmartHomeError.unsupported("Controlling \(accessory(for: outputID)?.name ?? "this speaker") from Home Assistant")
        }
        return entity
    }

    private func send(_ call: MediaServiceCall) async throws {
        try await smartHome().callService(domain: call.domain, service: call.service, data: call.data)
    }
}
