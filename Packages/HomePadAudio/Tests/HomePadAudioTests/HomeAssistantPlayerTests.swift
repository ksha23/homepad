import Foundation
import HomePadCore
import Testing
@testable import HomePadAudio

@Suite struct RemotePlayerMappingTests {
    static let accessories = [
        HomeAccessory(id: "ha:media_player.kitchen_homepod", name: "Kitchen HomePod", room: "Kitchen", kind: .mediaPlayer,
                      backend: .homeAssistant, state: AccessoryState(isOn: true, mediaTitle: "Lovers Rock", mediaArtist: "TV Girl", volume: 0.3)),
        HomeAccessory(id: "ha:media_player.sonos_one", name: "Sonos One", room: "Bedroom", kind: .mediaPlayer,
                      backend: .homeAssistant, state: AccessoryState(isOn: false, volume: 0.2)),
        HomeAccessory(id: "ha:light.kitchen", name: "Kitchen Lights", room: "Kitchen", kind: .light, backend: .homeAssistant),
        HomeAccessory(id: "hk:1234", name: "HomePod mini", room: "Office", kind: .mediaPlayer, backend: .homeKit),
    ]

    @Test func leavesOutMusicAssistantDashboards() {
        let dashboard = HomeAccessory(id: "ha:media_player.kitchen_display", name: "Kitchen Display", kind: .mediaPlayer,
                                      backend: .homeAssistant, integration: "music_assistant", deviceClass: "tv")
        #expect(RemotePlayerMapper.outputs(from: Self.accessories + [dashboard]).count == 3)
    }

    @Test func mapsOnlyMediaPlayers() {
        let outputs = RemotePlayerMapper.outputs(from: Self.accessories)
        #expect(outputs.map(\.id) == ["ha:media_player.sonos_one", "ha:media_player.kitchen_homepod", "hk:1234"])
        #expect(outputs.allSatisfy { $0.kind == .homeAssistantPlayer })
        #expect(outputs.map(\.name) == ["Bedroom Sonos One", "Kitchen HomePod", "Office HomePod mini"])
        #expect(outputs.map(\.isActive) == [false, true, false])
        #expect(outputs.map(\.volume) == [0.2, 0.3, nil])
    }

    @Test func extractsEntityIDs() {
        #expect(RemotePlayerMapper.entityID(for: "ha:media_player.kitchen") == "media_player.kitchen")
        #expect(RemotePlayerMapper.entityID(for: "media_player.kitchen") == "media_player.kitchen")
        #expect(RemotePlayerMapper.entityID(for: "ha:light.kitchen") == nil)
        #expect(RemotePlayerMapper.entityID(for: "hk:1234") == nil)
    }

    @Test func findsSpokenSpeakerNames() {
        let outputs = RemotePlayerMapper.outputs(from: Self.accessories)
        #expect(RemotePlayerMapper.find("kitchen HomePod", in: outputs)?.id == "ha:media_player.kitchen_homepod")
        #expect(RemotePlayerMapper.find("the kitchen", in: outputs)?.id == "ha:media_player.kitchen_homepod")
        #expect(RemotePlayerMapper.find("bedroom speaker", in: outputs)?.id == "ha:media_player.sonos_one")
        #expect(RemotePlayerMapper.find("sonos", in: outputs)?.id == "ha:media_player.sonos_one")
        #expect(RemotePlayerMapper.find("garage", in: outputs) == nil)
        #expect(RemotePlayerMapper.find("", in: outputs) == nil)
    }
}

@Suite struct MediaServiceCallTests {
    @Test func playMediaPayload() {
        let call = MediaServiceCall.playMedia(entityID: "media_player.kitchen", contentID: "https://ice1.somafm.com/groovesalad-128-mp3")
        #expect(call.domain == "media_player")
        #expect(call.service == "play_media")
        #expect(call.data == [
            "entity_id": "media_player.kitchen",
            "media_content_id": "https://ice1.somafm.com/groovesalad-128-mp3",
            "media_content_type": "music",
        ])
    }

    @Test func seekPayload() {
        let call = MediaServiceCall.seek(entityID: "media_player.kitchen", to: 64.4)
        #expect(call.service == "media_seek")
        #expect(call.data == ["entity_id": "media_player.kitchen", "seek_position": 64])
    }

    @Test func volumeIsClampedAndRounded() {
        #expect(MediaServiceCall.volumeSet(entityID: "media_player.a", level: 0.456).data["volume_level"] == .number(0.46))
        #expect(MediaServiceCall.volumeSet(entityID: "media_player.a", level: 1.7).data["volume_level"] == .number(1))
        #expect(MediaServiceCall.volumeSet(entityID: "media_player.a", level: -1).data["volume_level"] == .number(0))
        #expect(MediaServiceCall.volumeSet(entityID: "media_player.a", level: 0.5).service == "volume_set")
    }

    @Test func joinLeavesLeaderOutOfMembers() {
        let call = MediaServiceCall.join(leader: "media_player.a", members: ["media_player.b", "media_player.a", "media_player.c"])
        #expect(call.service == "join")
        #expect(call.data == ["entity_id": "media_player.a", "group_members": ["media_player.b", "media_player.c"]])
        #expect(MediaServiceCall.unjoin(entityID: "media_player.b").data == ["entity_id": "media_player.b"])
    }

    @Test func transportServices() {
        #expect(MediaServiceCall.transport(entityID: "media_player.a", .play).service == "media_play")
        #expect(MediaServiceCall.transport(entityID: "media_player.a", .next).service == "media_next_track")
        #expect(MediaServiceCall.transport(entityID: "media_player.a", .previous).service == "media_previous_track")
    }
}

@MainActor @Suite struct RemotePlayerControllerTests {
    @Test func homeKitSpeakersUseAccessoryCommands() async throws {
        let home = RecordingSmartHome(accessories: RemotePlayerMappingTests.accessories)
        let controller = RemotePlayerController { home }
        try await controller.setVolume(0.4, on: "hk:1234")
        try await controller.transport(.pause, on: "hk:1234")
        #expect(home.calls.isEmpty)
        #expect(home.commands == [.setVolume(0.4), .pause])
        await #expect(throws: SmartHomeError.self) {
            try await controller.seek(to: 10, on: "hk:1234")
        }
    }

    @Test func groupsAndSetsVolumeWithServiceCalls() async throws {
        let home = RecordingSmartHome(accessories: RemotePlayerMappingTests.accessories)
        let controller = RemotePlayerController { home }
        try await controller.group(leader: "ha:media_player.kitchen_homepod", members: ["ha:media_player.sonos_one"])
        try await controller.setVolume(0.25, on: "ha:media_player.sonos_one")
        #expect(home.calls == [
            .join(leader: "media_player.kitchen_homepod", members: ["media_player.sonos_one"]),
            .volumeSet(entityID: "media_player.sonos_one", level: 0.25),
        ])
    }
}
