import Foundation
import HomePadCore
import Observation

/// A pretend Home Assistant with Music Assistant for the simulator, which has no
/// real one. It is a `SmartHomeService`, so the Audio module drives it exactly like
/// the real smart home service: `config_entries/get`, `music_assistant.*` actions
/// with JSON answers, and `media_player.*` calls that change the demo speakers.
/// Enabled with `-HomePadAudioDemo YES`. It never touches the network.
@MainActor
@Observable
final class DemoMusicAssistantHome: SmartHomeService {
    var accessories: [HomeAccessory]
    let scenes: [HomeScene] = []
    let cameras: [HomeCamera] = []
    let connectedBackends: Set<SmartHomeBackend> = [.homeAssistant]
    let favoriteAccessoryIDs: [HomeAccessory.ID] = []
    @ObservationIgnored var queues: [String: (tracks: [DemoMusicCatalog.Track], index: Int)] = [:]

    static let entry: JSONValue = [
        "entry_id": "01JDEMOMUSICASSISTANT000", "domain": "music_assistant", "title": "Music Assistant",
        "state": "loaded", "disabled_by": .null,
    ]

    init() {
        let tracks = DemoMusicCatalog.tracks
        accessories = [
            Self.speaker("living_room_homepods", "Living Room HomePods", room: "Living Room", model: "HomePod", volume: 0.42),
            Self.speaker("kitchen", "Kitchen", room: "Kitchen", model: "HomePod mini", volume: 0.3),
            Self.speaker("office_sonos", "Office Sonos", room: "Office", model: "Sonos Era 100", volume: 0.25),
            Self.speaker("bedroom", "Bedroom", room: "Bedroom", model: "HomePod mini", volume: 0.18),
        ]
        start(Array(tracks.prefix(6)), on: "ha:media_player.living_room_homepods", position: 72)
        join("ha:media_player.living_room_homepods", members: ["ha:media_player.kitchen"])
        start(Array(tracks[2...5]), on: "ha:media_player.office_sonos", position: 41)
        update("ha:media_player.office_sonos") { $0.isPlaying = false }
    }

    // MARK: SmartHomeService

    func refresh() async {}
    func activateScene(_ sceneID: HomeScene.ID) async throws {}
    func snapshot(cameraID: HomeCamera.ID) async throws -> Data? { nil }
    func setFavorite(_ accessoryID: HomeAccessory.ID, isFavorite: Bool) {}

    func perform(_ command: AccessoryCommand, on accessoryID: HomeAccessory.ID) async throws {
        switch command {
        case .play: update(accessoryID) { $0.isPlaying = true }
        case .pause: update(accessoryID) { $0.isPlaying = false }
        case .setVolume(let level): update(accessoryID) { $0.volume = level }
        default: break
        }
    }

    func callService(domain: String, service: String, data: JSONValue) async throws {
        let ids = (data["entity_id"]?.arrayValue?.compactMap(\.stringValue) ?? data["entity_id"]?.stringValue.map { [$0] } ?? [])
            .map { "ha:\($0)" }
        for id in ids { try handle(domain: domain, service: service, data: data, on: id) }
    }

    func sendCommand(_ type: String, data: JSONValue) async throws -> JSONValue {
        switch type {
        case SmartHomeCommandType.configEntries:
            return data["domain"]?.stringValue == MusicAssistantAction.domain ? [Self.entry] : []
        case SmartHomeCommandType.callService:
            try await Task.sleep(for: .milliseconds(150))
            return ["context": ["id": "demo"], "response": try respond(to: data)]
        default:
            throw SmartHomeError.unsupported(type)
        }
    }

    // MARK: Actions with answers

    private func respond(to call: JSONValue) throws -> JSONValue {
        let fields = call["service_data"] ?? [:]
        switch call["service"]?.stringValue {
        case "search":
            let query = (fields["name"]?.stringValue ?? "").lowercased()
            func matches(_ item: MAMediaItem) -> Bool {
                query.isEmpty || item.name.lowercased().contains(query)
                    || item.artists.contains { $0.lowercased().contains(query) } || query.contains(item.name.lowercased())
            }
            let types: [(String, MAMediaItem.MediaType)] = [
                ("artists", .artist), ("albums", .album), ("tracks", .track), ("playlists", .playlist), ("radio", .radio),
            ]
            var response: [String: JSONValue] = ["audiobooks": [], "podcasts": []]
            for (key, type) in types {
                response[key] = .array(DemoMusicCatalog.items(of: type).filter(matches).prefix(12).map(\.json))
            }
            return .object(response)
        case "get_library":
            let type = MAMediaItem.MediaType(rawValue: fields["media_type"]?.stringValue ?? "") ?? .track
            var items = DemoMusicCatalog.items(of: type)
            if fields["favorite"]?.boolValue == true { items = items.filter(\.isFavorite) }
            if fields["order_by"]?.stringValue == "timestamp_added_desc" { items.reverse() }
            return ["items": .array(items.map(\.json)), "limit": 25, "offset": 0,
                    "order_by": fields["order_by"] ?? "name", "media_type": .string(type.rawValue)]
        case "get_queue":
            guard let entity = call["target"]?["entity_id"]?.stringValue else { return [:] }
            return [entity: queueJSON(for: "ha:\(entity)")]
        default:
            throw SmartHomeError.unsupported(call["service"]?.stringValue ?? "action")
        }
    }

    private func queueJSON(for id: String) -> JSONValue {
        guard let queue = queues[id], let accessory = accessories.first(where: { $0.id == id }) else { return .null }
        let current = queue.tracks[queue.index]
        let next = queue.index + 1 < queue.tracks.count ? queue.tracks[queue.index + 1] : nil
        return [
            "queue_id": .string(id), "active": true, "name": .string(accessory.name), "items": .number(Double(queue.tracks.count)),
            "shuffle_enabled": false, "repeat_mode": "off", "current_index": .number(Double(queue.index)),
            "elapsed_time": .number(accessory.state.mediaPosition ?? 0),
            "current_item": current.queueJSON(id: "\(queue.index)"),
            "next_item": next.map { $0.queueJSON(id: "\(queue.index + 1)") } ?? .null,
        ]
    }

    // MARK: Calls that change the speakers

    private func handle(domain: String, service: String, data: JSONValue, on id: String) throws {
        switch (domain, service) {
        case ("media_player", "media_play"): update(id) { $0.isPlaying = true; $0.mediaPositionUpdatedAt = Date() }
        case ("media_player", "media_pause"), ("media_player", "media_stop"): pause(id)
        case ("media_player", "media_play_pause"):
            if accessories.first(where: { $0.id == id })?.state.isPlaying == true { pause(id) } else { update(id) { $0.isPlaying = true } }
        case ("media_player", "media_next_track"): step(id, by: 1)
        case ("media_player", "media_previous_track"): step(id, by: -1)
        case ("media_player", "media_seek"):
            update(id) { $0.mediaPosition = data["seek_position"]?.doubleValue; $0.mediaPositionUpdatedAt = Date() }
        case ("media_player", "volume_set"): update(id) { $0.volume = data["volume_level"]?.doubleValue }
        case ("media_player", "join"): join(id, members: (data["group_members"]?.arrayValue ?? []).compactMap(\.stringValue).map { "ha:\($0)" })
        case ("media_player", "unjoin"): unjoin(id)
        case ("music_assistant", "play_media"):
            let uri = data["media_id"]?.arrayValue?.first?.stringValue ?? data["media_id"]?.stringValue ?? ""
            let catalog = [MAMediaItem.MediaType.track, .album, .artist, .playlist, .radio].flatMap(DemoMusicCatalog.items(of:))
            let item = catalog.first { $0.uri == uri || $0.name.localizedCaseInsensitiveCompare(uri) == .orderedSame }
                ?? DemoMusicCatalog.trackItems[0]
            if item.mediaType == .radio {
                playRadio(item, on: id)
            } else {
                start(DemoMusicCatalog.queue(for: item), on: id)
            }
        case ("music_assistant", "transfer_queue"):
            guard let source = data["source_player"]?.stringValue.map({ "ha:\($0)" }), let queue = queues[source],
                  let state = accessories.first(where: { $0.id == source })?.state else { return }
            queues[id] = queue
            update(id) { target in
                target.mediaTitle = state.mediaTitle; target.mediaArtist = state.mediaArtist; target.mediaAlbum = state.mediaAlbum
                target.mediaDuration = state.mediaDuration; target.mediaPosition = state.mediaPosition
                target.mediaPositionUpdatedAt = state.mediaPositionUpdatedAt; target.isPlaying = true
            }
            clear(source)
        default:
            throw SmartHomeError.unsupported("\(domain).\(service)")
        }
    }
}
