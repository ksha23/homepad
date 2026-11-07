import Foundation
import Testing
@testable import HomePadCore

/// A smart home stub that records raw commands and answers with a canned result.
@MainActor
private final class RecordingSmartHome: SmartHomeService {
    var accessories: [HomeAccessory] = []
    var scenes: [HomeScene] = []
    var cameras: [HomeCamera] = []
    var connectedBackends: Set<SmartHomeBackend> = [.homeAssistant]
    var favoriteAccessoryIDs: [HomeAccessory.ID] = []
    var sent: [(type: String, data: JSONValue)] = []
    var result: JSONValue = .null

    func refresh() async {}
    func perform(_ command: AccessoryCommand, on accessoryID: HomeAccessory.ID) async throws {}
    func activateScene(_ sceneID: HomeScene.ID) async throws {}
    func snapshot(cameraID: HomeCamera.ID) async throws -> Data? { nil }
    func setFavorite(_ accessoryID: HomeAccessory.ID, isFavorite: Bool) {}

    func sendCommand(_ type: String, data: JSONValue) async throws -> JSONValue {
        sent.append((type, data))
        return result
    }
}

@MainActor @Suite struct SmartHomeCommandTests {
    @Test func defaultBackendsDoNotSupportRawCommands() async {
        let demo = DemoSmartHomeService()
        await #expect(throws: SmartHomeError.self) { try await demo.sendCommand("config_entries/get", data: [:]) }
    }

    @Test func callServiceForResponseAsksForTheResponse() async throws {
        let home = RecordingSmartHome()
        home.result = ["context": ["id": "abc"], "response": ["tracks": []]]
        let response = try await home.callServiceForResponse(
            domain: "music_assistant", service: "get_queue", target: ["entity_id": "media_player.kitchen"]
        )
        #expect(response == ["tracks": []])
        let sent = try #require(home.sent.first)
        #expect(sent.type == "call_service")
        #expect(sent.data["domain"] == "music_assistant")
        #expect(sent.data["service"] == "get_queue")
        #expect(sent.data["return_response"] == true)
        #expect(sent.data["service_data"] == [:])
        #expect(sent.data["target"] == ["entity_id": "media_player.kitchen"])
    }

    @Test func integrationEntriesFilterByDomain() async throws {
        let home = RecordingSmartHome()
        home.result = [
            ["entry_id": "01JA0000000000000000000001", "domain": "music_assistant", "title": "Music Assistant",
             "state": "loaded", "disabled_by": nil],
            ["domain": "broken"],
        ]
        let entries = try await home.integrationEntries(domain: "music_assistant")
        #expect(home.sent.first?.type == "config_entries/get")
        #expect(home.sent.first?.data == ["domain": "music_assistant"])
        #expect(entries.count == 1)
        #expect(entries.first?.entryID == "01JA0000000000000000000001")
        #expect(entries.first?.isLoaded == true)
    }

    @Test func browseMediaSendsBothIDsOrNeither() async throws {
        let home = RecordingSmartHome()
        _ = try await home.browseMedia(entityID: "media_player.kitchen")
        _ = try await home.browseMedia(entityID: "media_player.kitchen", contentType: "playlists", contentID: "playlists")
        #expect(home.sent[0].data == ["entity_id": "media_player.kitchen"])
        #expect(home.sent[1].data == [
            "entity_id": "media_player.kitchen", "media_content_type": "playlists", "media_content_id": "playlists",
        ])
        #expect(home.sent.allSatisfy { $0.type == "media_player/browse_media" })
    }

    @Test func accessoryIntegrationFieldsDecodeFromOlderData() throws {
        let old = #"{"id":"ha:media_player.kitchen","name":"Kitchen","kind":"mediaPlayer","backend":"homeAssistant","capabilities":[],"state":{"isReachable":true}}"#
        let accessory = try JSONDecoder().decode(HomeAccessory.self, from: Data(old.utf8))
        #expect(accessory.integration == nil)
        #expect(accessory.state.mediaGroupMemberIDs == nil)
    }
}
