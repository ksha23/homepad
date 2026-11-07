import Foundation
import HomePadCore

/// Playing through Music Assistant: items, spoken searches, moving the queue,
/// multi-room groups and volume.
extension MusicAssistantService {
    /// Plays an item on `playerID`, or on the chosen speaker.
    func play(_ item: MAMediaItem, on playerID: String? = nil,
              enqueue: MusicAssistantAction.Enqueue = .replace) async throws {
        let player = try resolve(playerID)
        try await client.play([item.uri], mediaType: item.mediaType, on: player.entityID, enqueue: enqueue)
        targetPlayerID = player.id
        lastError = nil
    }

    /// "Play Taylor Swift": searches every provider, plays the best match, and says what
    /// started. Falls back to Music Assistant's own lookup by name when search finds nothing.
    @discardableResult
    func playSearch(_ query: String, on playerID: String? = nil,
                    mediaType: MAMediaItem.MediaType? = nil) async throws -> String {
        let player = try resolve(playerID)
        var results: MASearchResults?
        if let entryID {
            results = try? await client.search(entryID: entryID, query: query, mediaTypes: mediaType.map { [$0] }, limit: 5)
        }
        if let best = results?.bestMatch(for: query, preferring: mediaType) {
            try await client.play([best.uri], mediaType: best.mediaType, on: player.entityID)
            targetPlayerID = player.id
            return "\(Self.describe(best)) on \(player.name)"
        }
        do {
            try await client.play([query], mediaType: mediaType, on: player.entityID)
        } catch {
            throw AudioError.nothingFound(query)
        }
        targetPlayerID = player.id
        return "\(query) on \(player.name)"
    }

    /// The active queue of a player, for Up Next. Nil when it has none or the call fails.
    func queue(for playerID: String?) async -> MAQueue? {
        guard let player = player(playerID) else { return nil }
        return try? await client.queue(entityID: player.entityID)
    }

    /// Plays on exactly these speakers. What plays moves to the new leader when the
    /// current speaker is not among them (`transfer_queue`), the others join the leader
    /// (`media_player.join`), and speakers taken out of the group let go (`media_player.unjoin`).
    func playOn(_ selection: [String]) async throws {
        let chosen = selection.compactMap(player)
        guard let first = chosen.first else { return }
        let chosenIDs = Set(chosen.map(\.id))
        let current = activePlayer
        let leader = chosen.first { $0.id == current?.id } ?? first
        for memberID in leader.groupMemberIDs where memberID != leader.id && !chosenIDs.contains(memberID) {
            try await remote.ungroup(memberID)
        }
        if leader.followsGroup { try await remote.ungroup(leader.id) }
        if let current, current.hasMedia, !chosenIDs.contains(current.id) {
            try await client.transferQueue(from: current.entityID, to: leader.entityID)
        }
        let followers = chosen.filter { $0.id != leader.id && !leader.groupMemberIDs.contains($0.id) }.map(\.id)
        if !followers.isEmpty {
            try await remote.group(leader: leader.id, members: followers)
        }
        targetPlayerID = leader.id
        lastError = nil
    }

    func setVolume(_ level: Double, on playerID: String) async throws {
        try await remote.setVolume(level, on: playerID)
    }

    /// The speaker to play on, or `noSpeaker` when Music Assistant has none.
    func resolve(_ playerID: String?) throws -> MusicAssistantPlayer {
        if let player = player(playerID) ?? targetPlayer { return player }
        throw AudioError.noMusicAssistantSpeaker
    }

    /// "“Anti-Hero” by Taylor Swift", "the playlist Chill Mix" or "Taylor Swift".
    static func describe(_ item: MAMediaItem) -> String {
        let artists = item.artists.formatted(.list(type: .and))
        switch item.mediaType {
        case .track: return artists.isEmpty ? "“\(item.name)”" : "“\(item.name)” by \(artists)"
        case .album: return artists.isEmpty ? item.name : "\(item.name) by \(artists)"
        case .playlist: return "the playlist \(item.name)"
        default: return item.name
        }
    }
}
