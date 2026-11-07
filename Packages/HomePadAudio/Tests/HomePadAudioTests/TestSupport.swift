import Foundation
import HomePadCore
@testable import HomePadAudio

/// A smart home service that records what the Audio module asks of it and answers
/// raw commands from canned JSON, the way Home Assistant would.
@MainActor
final class RecordingSmartHome: SmartHomeService {
    var accessories: [HomeAccessory]
    var scenes: [HomeScene] = []
    var cameras: [HomeCamera] = []
    var connectedBackends: Set<SmartHomeBackend> = [.homeAssistant]
    var favoriteAccessoryIDs: [HomeAccessory.ID] = []
    private(set) var calls: [MediaServiceCall] = []
    private(set) var commands: [AccessoryCommand] = []
    /// Raw commands, in order.
    private(set) var sent: [(type: String, data: JSONValue)] = []
    /// Answers for raw commands, keyed by command type, or `domain.service` for action calls.
    var answers: [String: JSONValue] = [:]
    private let failingDomain: String?

    init(accessories: [HomeAccessory], failingDomain: String? = nil) {
        self.accessories = accessories
        self.failingDomain = failingDomain
    }

    func refresh() async {}
    func perform(_ command: AccessoryCommand, on accessoryID: HomeAccessory.ID) async throws { commands.append(command) }
    func activateScene(_ sceneID: HomeScene.ID) async throws {}
    func snapshot(cameraID: HomeCamera.ID) async throws -> Data? { nil }
    func setFavorite(_ accessoryID: HomeAccessory.ID, isFavorite: Bool) {}

    func callService(domain: String, service: String, data: JSONValue) async throws {
        if domain == failingDomain { throw SmartHomeError.backend("Service \(domain).\(service) not found") }
        calls.append(MediaServiceCall(domain: domain, service: service, data: data))
    }

    func sendCommand(_ type: String, data: JSONValue) async throws -> JSONValue {
        sent.append((type, data))
        let key = type == SmartHomeCommandType.callService
            ? "\(data["domain"]?.stringValue ?? "").\(data["service"]?.stringValue ?? "")" : type
        guard let answer = answers[key] else { throw SmartHomeError.unsupported(key) }
        return answer
    }

    /// The action calls that asked for a response, as `domain.service`.
    var responseCalls: [String] {
        sent.filter { $0.type == SmartHomeCommandType.callService }
            .map { "\($0.data["domain"]?.stringValue ?? "").\($0.data["service"]?.stringValue ?? "")" }
    }

    /// Answers like a Home Assistant with Music Assistant: the config entry, a search
    /// for Taylor Swift and the kitchen's queue, from the fixtures.
    static func withMusicAssistant(_ accessories: [HomeAccessory]) -> RecordingSmartHome {
        let home = RecordingSmartHome(accessories: accessories)
        home.answers = [
            "config_entries/get": Fixture.result("ws_result_config_entries"),
            "music_assistant.search": Fixture.result("ws_result_ma_search"),
            "music_assistant.get_library": Fixture.result("ws_result_ma_get_library_playlists"),
            "music_assistant.get_queue": Fixture.result("ws_result_ma_get_queue"),
        ]
        return home
    }
}

/// Loads the WebSocket messages in `Fixtures/`, captured in the shape Home Assistant sends them.
enum Fixture {
    static func message(_ name: String) -> JSONValue {
        let url = Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures")!
        return try! JSONDecoder().decode(JSONValue.self, from: Data(contentsOf: url))
    }

    /// The `result` of a WebSocket result message.
    static func result(_ name: String) -> JSONValue {
        message(name)["result"] ?? .null
    }

    /// The `response` inside an action call's result.
    static func response(_ name: String) -> JSONValue {
        result(name)["response"] ?? .null
    }
}

/// Music Assistant speakers as Home Assistant reports them.
enum Speakers {
    static func player(_ object: String, _ name: String, room: String? = nil, model: String? = nil, title: String? = nil,
                       playing: Bool = false, group: [String]? = nil, deviceClass: String = "speaker") -> HomeAccessory {
        HomeAccessory(
            id: "ha:media_player.\(object)", name: name, room: room, kind: .mediaPlayer, backend: .homeAssistant,
            capabilities: [.power, .playback, .volume],
            state: AccessoryState(isOn: true, mediaTitle: title, mediaArtist: title == nil ? nil : "Taylor Swift",
                                  volume: 0.4, isPlaying: playing, mediaGroupMemberIDs: group),
            integration: "music_assistant", deviceClass: deviceClass, deviceModel: model
        )
    }

    static let kitchen = player("kitchen", "Kitchen", room: "Kitchen", model: "HomePod mini")
    static let living = player("living_room", "Living Room HomePods", room: "Living Room", model: "HomePod")
    static let office = player("office_sonos", "Office Sonos", room: "Office", model: "Sonos Era 100")
    static let display = player("kitchen_display", "Kitchen Display", deviceClass: "tv")
}
