import Foundation

/// Home Assistant WebSocket commands that answer with data, built on
/// `SmartHomeService.sendCommand(_:data:)`. Backends other than Home Assistant
/// throw `SmartHomeError.unsupported` for all of them.
public enum SmartHomeCommandType {
    /// `call_service`. With `return_response: true` the result carries a `response`.
    public static let callService = "call_service"
    /// `config_entries/get`, optionally filtered by `domain`.
    public static let configEntries = "config_entries/get"
    /// `media_player/browse_media` for one media player entity.
    public static let browseMedia = "media_player/browse_media"
}

/// One set-up integration instance, from Home Assistant's `config_entries/get`.
/// Actions such as `music_assistant.search` take its `entryID` as `config_entry_id`.
public struct SmartHomeIntegrationEntry: Identifiable, Hashable, Sendable {
    public var entryID: String
    /// The integration, for example `music_assistant`.
    public var domain: String
    /// The name shown in Home Assistant, for example "Music Assistant".
    public var title: String
    /// `loaded`, `setup_error`, `not_loaded` and so on.
    public var state: String
    /// Set when the person or Home Assistant disabled the entry.
    public var disabledBy: String?

    public var id: String { entryID }
    /// True when the integration is running and its actions work.
    public var isLoaded: Bool { state == "loaded" && disabledBy == nil }

    public init(entryID: String, domain: String, title: String, state: String, disabledBy: String? = nil) {
        self.entryID = entryID
        self.domain = domain
        self.title = title
        self.state = state
        self.disabledBy = disabledBy
    }

    /// Reads one element of the `config_entries/get` result. Nil when the ID or domain is missing.
    public init?(json: JSONValue) {
        guard let entryID = json["entry_id"]?.stringValue, let domain = json["domain"]?.stringValue else { return nil }
        self.init(
            entryID: entryID, domain: domain, title: json["title"]?.stringValue ?? domain,
            state: json["state"]?.stringValue ?? "unknown", disabledBy: json["disabled_by"]?.stringValue
        )
    }
}

public extension SmartHomeService {
    /// Calls an action and returns its response data (`return_response: true`), for
    /// actions such as `music_assistant.search`. Entity actions such as
    /// `music_assistant.get_queue` answer with an object keyed by entity ID.
    /// - Parameters:
    ///   - data: The action's fields (`service_data`).
    ///   - target: Optional target, for example `["entity_id": "media_player.kitchen"]`.
    func callServiceForResponse(domain: String, service: String, data: JSONValue = [:],
                                target: JSONValue? = nil) async throws -> JSONValue {
        var fields: [String: JSONValue] = [
            "domain": .string(domain),
            "service": .string(service),
            "service_data": data,
            "return_response": true,
        ]
        if let target { fields["target"] = target }
        let result = try await sendCommand(SmartHomeCommandType.callService, data: .object(fields))
        return result["response"] ?? .null
    }

    /// The set-up instances of one integration, for example `music_assistant`.
    func integrationEntries(domain: String) async throws -> [SmartHomeIntegrationEntry] {
        let result = try await sendCommand(SmartHomeCommandType.configEntries, data: ["domain": .string(domain)])
        return (result.arrayValue ?? []).compactMap(SmartHomeIntegrationEntry.init(json:))
    }

    /// One level of a media player's browse tree (`media_player/browse_media`).
    /// Leave both IDs nil for the top level. The result has `title`, `children` and
    /// `media_content_id` and `media_content_type` for each child.
    func browseMedia(entityID: String, contentType: String? = nil, contentID: String? = nil) async throws -> JSONValue {
        var fields: [String: JSONValue] = ["entity_id": .string(entityID)]
        if let contentType, let contentID {
            fields["media_content_type"] = .string(contentType)
            fields["media_content_id"] = .string(contentID)
        }
        return try await sendCommand(SmartHomeCommandType.browseMedia, data: .object(fields))
    }
}
