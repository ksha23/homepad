import Foundation
import HomePadCore
import Testing
@testable import HomePadAudio

/// Discovery, players, playing and multi-room through Music Assistant, against a
/// recorded smart home that answers like Home Assistant.
@MainActor @Suite struct MusicAssistantServiceTests {
    private let settings = SettingsStore(defaults: UserDefaults(suiteName: "audio.ma.\(UUID())")!)

    private func makeService(_ home: RecordingSmartHome) -> MusicAssistantService {
        MusicAssistantService(settings: settings, remote: RemotePlayerController { home }) { home }
    }

    @Test func findsTheConfigEntry() async {
        let home = RecordingSmartHome.withMusicAssistant([Speakers.kitchen])
        let service = makeService(home)
        await service.refreshStatus()
        #expect(service.entryID == "01JA0000000000000000000001")
        #expect(home.sent.first?.type == "config_entries/get")
        #expect(home.sent.first?.data == ["domain": "music_assistant"])
    }

    @Test func reportsMissingMusicAssistant() async {
        let home = RecordingSmartHome(accessories: [])
        home.answers = ["config_entries/get": []]
        let service = makeService(home)
        await service.refreshStatus()
        #expect(service.status == .notSetUp)
        let offline = makeService(RecordingSmartHome(accessories: []))
        await offline.refreshStatus()
        #expect(offline.status == .notSetUp, "no answer at all, as with HomeKit only, means not set up")
    }

    @Test func listsSpeakersWithoutDisplays() {
        let service = makeService(RecordingSmartHome(accessories: [Speakers.office, Speakers.kitchen, Speakers.display]))
        #expect(service.players.map(\.name) == ["Kitchen", "Office Sonos"])
        #expect(service.targetPlayer?.name == "Kitchen", "the first speaker until one is chosen")
        service.targetPlayerID = Speakers.office.id
        #expect(service.targetPlayer?.name == "Office Sonos")
    }

    @Test func activePlayerFollowsWhatPlays() {
        let playingOffice = Speakers.player("office_sonos", "Office Sonos", title: "Anti-Hero", playing: true)
        let pausedKitchen = Speakers.player("kitchen", "Kitchen", title: "Lavender Haze")
        let home = RecordingSmartHome(accessories: [pausedKitchen, playingOffice])
        let service = makeService(home)
        service.targetPlayerID = pausedKitchen.id
        #expect(service.activePlayer?.name == "Office Sonos", "a playing speaker beats a paused chosen one")
        home.accessories[1].state.isPlaying = false
        settings[AudioSettings.musicAssistantLastActivePlayer] = playingOffice.id
        #expect(service.activePlayer?.name == "Office Sonos", "the last active speaker while it still has music loaded")
        settings[AudioSettings.musicAssistantLastActivePlayer] = ""
        #expect(service.activePlayer?.name == "Kitchen")
    }

    @Test func playSearchPlaysTheBestMatchByURI() async throws {
        let home = RecordingSmartHome.withMusicAssistant([Speakers.kitchen, Speakers.office])
        let service = makeService(home)
        await service.refreshStatus()
        let started = try await service.playSearch("Taylor Swift", on: Speakers.office.id)
        #expect(started == "Taylor Swift on Office Sonos")
        #expect(home.responseCalls == ["music_assistant.search"])
        #expect(home.sent.last?.data["service_data"]?["config_entry_id"] == "01JA0000000000000000000001")
        #expect(home.calls == [MediaServiceCall(domain: "music_assistant", service: "play_media", data: [
            "entity_id": "media_player.office_sonos", "media_id": ["apple_music://artist/159260351"],
            "media_type": "artist", "enqueue": "replace",
        ])])
        #expect(service.targetPlayerID == Speakers.office.id)
    }

    @Test func playSearchFallsBackToLookupByName() async throws {
        let home = RecordingSmartHome.withMusicAssistant([Speakers.kitchen])
        home.answers["music_assistant.search"] = ["context": [:], "response": ["artists": [], "albums": [], "tracks": [],
                                                                               "playlists": [], "radio": []]]
        let service = makeService(home)
        await service.refreshStatus()
        _ = try await service.playSearch("morning jazz", mediaType: .playlist)
        #expect(home.calls.first?.data["media_id"] == ["morning jazz"])
        #expect(home.calls.first?.data["media_type"] == "playlist")
    }

    @Test func playOnMovesTheQueueAndGroups() async throws {
        let living = Speakers.player("living_room", "Living Room HomePods", title: "Anti-Hero", playing: true)
        let home = RecordingSmartHome.withMusicAssistant([living, Speakers.kitchen, Speakers.office])
        let service = makeService(home)
        service.targetPlayerID = living.id
        try await service.playOn([Speakers.office.id, Speakers.kitchen.id])
        #expect(home.calls == [
            MediaServiceCall(domain: "music_assistant", service: "transfer_queue", data: [
                "entity_id": "media_player.office_sonos", "source_player": "media_player.living_room", "auto_play": true,
            ]),
            .join(leader: "media_player.office_sonos", members: ["media_player.kitchen"]),
        ])
        #expect(service.targetPlayerID == Speakers.office.id)
    }

    @Test func playOnKeepsTheLeaderAndLetsGoOfOthers() async throws {
        let group = ["ha:media_player.living_room", "ha:media_player.kitchen"]
        let living = Speakers.player("living_room", "Living Room HomePods", title: "Anti-Hero", playing: true, group: group)
        let kitchen = Speakers.player("kitchen", "Kitchen", title: "Anti-Hero", playing: true, group: group)
        let home = RecordingSmartHome.withMusicAssistant([living, kitchen, Speakers.office])
        let service = makeService(home)
        service.targetPlayerID = living.id
        try await service.playOn([living.id, Speakers.office.id])
        #expect(home.calls == [
            .unjoin(entityID: "media_player.kitchen"),
            .join(leader: "media_player.living_room", members: ["media_player.office_sonos"]),
        ])
    }

    @Test func queueComesFromGetQueue() async {
        let home = RecordingSmartHome.withMusicAssistant([Speakers.kitchen])
        let queue = await makeService(home).queue(for: Speakers.kitchen.id)
        #expect(queue?.currentItem?.title == "Anti-Hero")
        #expect(home.sent.first?.data["target"] == ["entity_id": "media_player.kitchen"])
    }

    @Test func listenNowLoadsShelvesInParallel() async {
        let home = RecordingSmartHome.withMusicAssistant([Speakers.kitchen])
        let service = makeService(home)
        await service.refreshStatus()
        await service.loadHome()
        #expect(service.home.playlists.map(\.name) == ["Dinner Party", "Night Rider"])
        #expect(home.responseCalls.filter { $0 == "music_assistant.get_library" }.count == 6)
        let orders = Set(home.sent.compactMap { $0.data["service_data"]?["order_by"]?.stringValue })
        #expect(orders == ["last_played_desc", "timestamp_added_desc"])
    }
}
