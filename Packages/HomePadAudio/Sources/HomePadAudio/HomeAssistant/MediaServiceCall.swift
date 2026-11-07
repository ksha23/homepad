import Foundation
import HomePadCore

/// A Home Assistant `media_player` service call, built without side effects
/// so payloads are easy to test. `RemotePlayerController` sends them through
/// `services.smartHome.callService`.
struct MediaServiceCall: Equatable, Sendable {
    let domain: String
    let service: String
    let data: JSONValue

    /// Transport actions that map one to one onto `media_player` services.
    enum Transport: String, Sendable {
        case play = "media_play"
        case pause = "media_pause"
        case playPause = "media_play_pause"
        case next = "media_next_track"
        case previous = "media_previous_track"
        case stop = "media_stop"
    }

    /// `media_player.play_media` for a URL or an integration-specific content ID.
    static func playMedia(entityID: String, contentID: String, contentType: String = "music") -> MediaServiceCall {
        MediaServiceCall(domain: "media_player", service: "play_media", data: [
            "entity_id": .string(entityID),
            "media_content_id": .string(contentID),
            "media_content_type": .string(contentType),
        ])
    }

    /// `media_player.volume_set`, clamped to 0...1.
    static func volumeSet(entityID: String, level: Double) -> MediaServiceCall {
        let clamped = (max(0, min(1, level)) * 100).rounded() / 100
        return MediaServiceCall(domain: "media_player", service: "volume_set", data: [
            "entity_id": .string(entityID),
            "volume_level": .number(clamped),
        ])
    }

    /// `media_player.join`: `members` start playing whatever `leader` plays (Sonos, Music Assistant).
    static func join(leader: String, members: [String]) -> MediaServiceCall {
        MediaServiceCall(domain: "media_player", service: "join", data: [
            "entity_id": .string(leader),
            "group_members": .array(members.filter { $0 != leader }.map(JSONValue.string)),
        ])
    }

    /// `media_player.unjoin`: removes a player from its group.
    static func unjoin(entityID: String) -> MediaServiceCall {
        MediaServiceCall(domain: "media_player", service: "unjoin", data: ["entity_id": .string(entityID)])
    }

    /// `media_player.media_seek` to a position in seconds.
    static func seek(entityID: String, to seconds: TimeInterval) -> MediaServiceCall {
        MediaServiceCall(domain: "media_player", service: "media_seek", data: [
            "entity_id": .string(entityID),
            "seek_position": .number(max(0, seconds.rounded())),
        ])
    }

    static func transport(entityID: String, _ action: Transport) -> MediaServiceCall {
        MediaServiceCall(domain: "media_player", service: action.rawValue, data: ["entity_id": .string(entityID)])
    }
}
