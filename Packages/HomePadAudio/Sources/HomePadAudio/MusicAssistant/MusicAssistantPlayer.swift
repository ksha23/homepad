import Foundation
import HomePadCore

/// A Music Assistant player as Home Assistant exposes it: a `media_player` entity from
/// the `music_assistant` integration, such as a HomePod (through Music Assistant's
/// AirPlay provider) or a Sonos speaker. Built from the smart home accessory.
struct MusicAssistantPlayer: Identifiable, Hashable, Sendable {
    /// The kind of speaker, for its symbol.
    enum Model: Hashable, Sendable {
        case homePod, homePodMini, sonos, group, other

        var systemImage: String {
            switch self {
            case .homePod: "homepod.fill"
            case .homePodMini: "homepod.mini.fill"
            case .sonos: "hifispeaker.fill"
            case .group: "hifispeaker.2.fill"
            case .other: "hifispeaker.fill"
            }
        }
    }

    /// The accessory ID, for example `ha:media_player.kitchen`.
    let id: String
    /// The Home Assistant entity ID, for example `media_player.kitchen`.
    let entityID: String
    let name: String
    let room: String?
    let model: Model
    let isReachable: Bool
    let isPlaying: Bool
    let volume: Double?
    let title: String?
    let artist: String?
    let album: String?
    let artworkURL: URL?
    /// Accessory IDs that play in sync with this player (Home Assistant's `group_members`).
    let groupMemberIDs: [String]

    /// The integration name Music Assistant players carry in Home Assistant's entity registry.
    static let integration = "music_assistant"

    /// Nil for accessories that are not Music Assistant speakers. Music Assistant's
    /// dashboard displays (device class `tv`) cannot play music, so they are skipped.
    init?(accessory: HomeAccessory) {
        guard accessory.kind == .mediaPlayer, accessory.integration == Self.integration,
              accessory.deviceClass != "tv",
              let entityID = RemotePlayerMapper.entityID(for: accessory.id) else { return nil }
        let state = accessory.state
        id = accessory.id
        self.entityID = entityID
        name = RemotePlayerMapper.displayName(for: accessory)
        room = accessory.room
        isReachable = state.isReachable
        isPlaying = state.isPlaying ?? false
        volume = state.volume
        title = state.mediaTitle
        artist = state.mediaArtist
        album = state.mediaAlbum
        artworkURL = state.mediaArtworkURL
        groupMemberIDs = state.mediaGroupMemberIDs ?? []
        model = Self.model(name: accessory.name, deviceModel: accessory.deviceModel, members: groupMemberIDs, id: accessory.id)
    }

    /// True when something is loaded, playing or paused.
    var hasMedia: Bool { title != nil }

    /// A group player Music Assistant manages (its members do not include itself).
    var isGroupPlayer: Bool { !groupMemberIDs.isEmpty && !groupMemberIDs.contains(id) }

    /// True when this player leads a multi-room group it is part of.
    var leadsGroup: Bool { groupMemberIDs.count > 1 && groupMemberIDs.first == id }

    /// True when this player follows another player's group.
    var followsGroup: Bool { groupMemberIDs.count > 1 && groupMemberIDs.contains(id) && groupMemberIDs.first != id }

    /// "Anti-Hero · Taylor Swift", or nil when idle.
    var nowPlayingLine: String? {
        guard let title else { return nil }
        return [title, artist].compactMap { $0 }.joined(separator: " · ")
    }

    private static func model(name: String, deviceModel: String?, members: [String], id: String) -> Model {
        if !members.isEmpty && !members.contains(id) { return .group }
        let text = "\(deviceModel ?? "") \(name)".lowercased()
        if text.contains("homepod mini") || text.contains("audioaccessory5") { return .homePodMini }
        if text.contains("homepod") || text.contains("audioaccessory") { return .homePod }
        if text.contains("sonos") { return .sonos }
        return .other
    }
}
