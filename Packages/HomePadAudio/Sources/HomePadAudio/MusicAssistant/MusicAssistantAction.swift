import Foundation
import HomePadCore

/// Home Assistant `music_assistant.*` action calls, built without side effects so
/// the payloads are easy to test. Field names follow the integration's
/// `services.yaml` and `services.py` (home-assistant/core, `components/music_assistant`).
struct MusicAssistantAction: Equatable, Sendable {
    static let domain = "music_assistant"

    /// Where `play_media` puts the new items (`enqueue`).
    enum Enqueue: String, Sendable {
        /// Play now and keep the rest of the queue.
        case play
        /// Replace the queue and play.
        case replace
        /// Play after the current item.
        case next
        /// Add to the end of the queue.
        case add
    }

    let service: String
    let data: JSONValue
    /// The entity for entity actions (`play_media`, `get_queue`, `transfer_queue`).
    let target: JSONValue?
    /// True for actions that answer with data (`search`, `get_library`, `get_queue`).
    let returnsResponse: Bool

    /// `music_assistant.search` across every provider Music Assistant has (Apple Music,
    /// Spotify, radio and the library). Answers with one list per media type.
    /// `username` is the Music Assistant user to search as (see `addUser`).
    static func search(entryID: String, query: String, mediaTypes: [MAMediaItem.MediaType]? = nil,
                       limit: Int = 8, libraryOnly: Bool = false, username: String? = nil) -> MusicAssistantAction {
        var data: [String: JSONValue] = [
            "config_entry_id": .string(entryID),
            "name": .string(query),
            "limit": .number(Double(limit)),
            "library_only": .bool(libraryOnly),
        ]
        if let mediaTypes, !mediaTypes.isEmpty {
            data["media_type"] = .array(mediaTypes.map { .string($0.rawValue) })
        }
        addUser(username, to: &data)
        return MusicAssistantAction(service: "search", data: .object(data), target: nil, returnsResponse: true)
    }

    /// `music_assistant.get_library` for one media type.
    /// - Parameters:
    ///   - favorite: Only favorites when true.
    ///   - orderBy: One of the integration's sort keys, for example `last_played_desc`,
    ///     `timestamp_added_desc` or `name`.
    static func library(entryID: String, mediaType: MAMediaItem.MediaType, favorite: Bool? = nil,
                        orderBy: String? = nil, limit: Int = 25, offset: Int = 0, username: String? = nil) -> MusicAssistantAction {
        var data: [String: JSONValue] = [
            "config_entry_id": .string(entryID),
            "media_type": .string(mediaType.rawValue),
            "limit": .number(Double(limit)),
            "offset": .number(Double(offset)),
        ]
        if let favorite { data["favorite"] = .bool(favorite) }
        if let orderBy { data["order_by"] = .string(orderBy) }
        addUser(username, to: &data)
        return MusicAssistantAction(service: "get_library", data: .object(data), target: nil, returnsResponse: true)
    }

    /// `music_assistant.play_media` on one player. `mediaIDs` are Music Assistant URIs from
    /// search or the library, or plain names that Music Assistant looks up itself.
    static func playMedia(entityID: String, mediaIDs: [String], mediaType: MAMediaItem.MediaType? = nil,
                          enqueue: Enqueue = .replace, radioMode: Bool? = nil, username: String? = nil) -> MusicAssistantAction {
        var data: [String: JSONValue] = [
            "media_id": .array(mediaIDs.map(JSONValue.string)),
            "enqueue": .string(enqueue.rawValue),
        ]
        if let mediaType, mediaType != .unknown { data["media_type"] = .string(mediaType.rawValue) }
        if let radioMode { data["radio_mode"] = .bool(radioMode) }
        addUser(username, to: &data)
        return MusicAssistantAction(service: "play_media", data: .object(data), target: entity(entityID), returnsResponse: false)
    }

    /// `music_assistant.get_queue`. Answers with the queue keyed by entity ID.
    static func getQueue(entityID: String) -> MusicAssistantAction {
        MusicAssistantAction(service: "get_queue", data: [:], target: entity(entityID), returnsResponse: true)
    }

    /// `music_assistant.transfer_queue`: moves what plays on `sourceEntityID` to `entityID`.
    static func transferQueue(to entityID: String, from sourceEntityID: String?, autoPlay: Bool = true) -> MusicAssistantAction {
        var data: [String: JSONValue] = ["auto_play": .bool(autoPlay)]
        if let sourceEntityID { data["source_player"] = .string(sourceEntityID) }
        return MusicAssistantAction(service: "transfer_queue", data: .object(data), target: entity(entityID), returnsResponse: false)
    }

    /// The same call in `callService` form, with the target folded into the data,
    /// for actions that do not answer.
    var serviceData: JSONValue {
        guard var fields = data.objectValue else { return data }
        if let entity = target?["entity_id"] { fields["entity_id"] = entity }
        return .object(fields)
    }

    /// The Music Assistant user a request is for, by name. Music Assistant then
    /// uses only the music sources that user may use, such as their own
    /// Spotify account, and their library. Left out when there is none, since
    /// Home Assistant before 2026.7 refuses an unknown field, and Music
    /// Assistant otherwise uses the Home Assistant user of HomePad's token.
    private static func addUser(_ username: String?, to data: inout [String: JSONValue]) {
        guard let username, !username.isEmpty else { return }
        data["username"] = .string(username)
    }

    private static func entity(_ entityID: String) -> JSONValue {
        ["entity_id": .string(entityID)]
    }
}
