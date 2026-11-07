import Foundation
import HomePadCore

/// A player's active queue from `music_assistant.get_queue` (Home Assistant's
/// `QUEUE_DETAILS_SCHEMA`). The action answers keyed by entity ID, so
/// `init(response:entityID:)` picks the player's entry first.
struct MAQueue: Equatable, Sendable {
    /// One entry of the queue (`QUEUE_ITEM_SCHEMA`).
    struct Item: Identifiable, Equatable, Sendable {
        var id: String
        /// Music Assistant's display name, usually "Artist - Title".
        var name: String
        var duration: TimeInterval?
        var mediaItem: MAMediaItem?
        /// The song title a radio stream reports right now.
        var streamTitle: String?

        init?(json: JSONValue?) {
            guard let json, let id = json["queue_item_id"]?.stringValue, let name = json["name"]?.stringValue else { return nil }
            self.id = id
            self.name = name
            duration = json["duration"]?.doubleValue
            mediaItem = json["media_item"].flatMap(MAMediaItem.init(json:))
            streamTitle = json["stream_title"]?.stringValue
        }

        /// The title to show: the stream's current song, then the item, then the queue name.
        var title: String { streamTitle ?? mediaItem?.name ?? name }
        var subtitle: String? { mediaItem.map(\.subtitle) }
    }

    var queueID: String
    var isActive: Bool
    var name: String
    var itemCount: Int
    var isShuffled: Bool
    /// `off`, `one` or `all`.
    var repeatMode: String
    var currentIndex: Int?
    var elapsed: TimeInterval
    var currentItem: Item?
    var nextItem: Item?

    /// Reads the entry for `entityID` from a `get_queue` response, or the response itself
    /// when it is not keyed (a single-entity answer). Nil when there is no queue.
    init?(response: JSONValue, entityID: String) {
        let json = response[entityID] ?? response
        guard let queueID = json["queue_id"]?.stringValue else { return nil }
        self.queueID = queueID
        isActive = json["active"]?.boolValue ?? false
        name = json["name"]?.stringValue ?? ""
        itemCount = json["items"]?.intValue ?? 0
        isShuffled = json["shuffle_enabled"]?.boolValue ?? false
        repeatMode = json["repeat_mode"]?.stringValue ?? "off"
        currentIndex = json["current_index"]?.intValue
        elapsed = json["elapsed_time"]?.doubleValue ?? 0
        currentItem = Item(json: json["current_item"])
        nextItem = Item(json: json["next_item"])
    }

    /// How many items are left after the current one.
    var remainingCount: Int {
        guard let currentIndex else { return itemCount }
        return max(0, itemCount - currentIndex - 1)
    }
}
