import Foundation
import HomePadCore
import Testing
@testable import HomePadAudio

/// "Play this in the kitchen" goes through Music Assistant and leaves iPad audio alone,
/// and Now Playing follows the house's music when Music Assistant is the source.
@MainActor @Suite struct HomeSpeakerFlowTests {
    /// The media service holds `AppServices` unowned, as the app keeps both alive, so the suite keeps it too.
    private let services = AppServices(settings: SettingsStore(defaults: UserDefaults(suiteName: "audio.flow.\(UUID())")!))
    private let sonos = HomeAccessory(id: "ha:media_player.sonos_one", name: "Sonos One", room: "Bedroom", kind: .mediaPlayer,
                                      backend: .homeAssistant, state: AccessoryState(isOn: false, volume: 0.2), integration: "sonos")

    private func makeMedia(_ accessories: [HomeAccessory]? = nil) async -> (AudioMediaService, RecordingSmartHome) {
        let home = RecordingSmartHome.withMusicAssistant(accessories ?? [Speakers.kitchen, Speakers.office, sonos])
        services.smartHome = home
        let media = AudioMediaService(services: services)
        services.media = media
        await media.musicAssistant.refreshStatus()
        return (media, home)
    }

    @Test func selectingASpeakerRoutesSearchesToMusicAssistant() async throws {
        let (media, home) = await makeMedia()
        try await media.select(outputID: Speakers.kitchen.id)
        #expect(media.remoteTargetID == Speakers.kitchen.id)
        #expect(media.currentRouteName == "Kitchen")

        let answer = try await media.playSearch("Taylor Swift")
        #expect(answer == "Taylor Swift on Kitchen")
        #expect(home.responseCalls == ["music_assistant.search"])
        #expect(home.calls.last?.domain == "music_assistant")
        #expect(home.calls.last?.data["entity_id"] == "media_player.kitchen")
        #expect(media.activeKind == nil)

        await media.pause()
        #expect(home.calls.last == .transport(entityID: "media_player.kitchen", .pause))
        media.controlThisIPad()
        #expect(media.remoteTargetID == nil)
    }

    @Test func spokenRoomPicksTheSpeaker() async throws {
        let (media, home) = await makeMedia()
        let answer = try await media.playSearch("Taylor Swift in the office")
        #expect(answer == "Taylor Swift on Office Sonos")
        #expect(home.calls.last?.data["entity_id"] == "media_player.office_sonos")
        #expect(media.remoteTargetID == Speakers.office.id, "This iPad stays the source, so the speaker becomes the focus")
    }

    @Test func speakersOutsideMusicAssistantCannotSearch() async {
        let (media, _) = await makeMedia()
        await #expect(throws: AudioError.musicAssistantUnavailable) { try await media.playSearch("jazz on the bedroom sonos one") }
    }

    @Test func musicAssistantSourceDrivesNowPlaying() async throws {
        let playing = Speakers.player("office_sonos", "Office Sonos", title: "Anti-Hero", playing: true)
        let (media, home) = await makeMedia([Speakers.kitchen, playing])
        #expect(media.canChooseMusicSource)
        #expect(media.nowPlaying == nil, "This iPad is the default source")
        #expect(media.elsewhereInTheHouse.map(\.name) == ["Office Sonos"])

        media.setMusicSource(.musicAssistant)
        #expect(media.musicSource == .musicAssistant)
        #expect(media.nowPlaying?.title == "Anti-Hero")
        #expect(media.nowPlaying?.source == .homeAssistant)
        #expect(media.currentRouteName == "Office Sonos")
        await media.nextTrack()
        #expect(home.calls.last == .transport(entityID: "media_player.office_sonos", .next))

        _ = try await media.playSearch("Midnights album")
        #expect(home.calls.last?.data["media_id"] == ["apple_music://album/1650841512"])
    }

    @Test func sourceChoiceIsRememberedPerMember() async {
        let (media, _) = await makeMedia()
        let member = HouseholdMember(name: "Kyle")
        services.household.add(member)
        services.household.select(member.id)
        media.setMusicSource(.musicAssistant)
        #expect(services.household.activeMember?.preferences[AudioSettings.musicSourcePreference] == "musicAssistant")
        #expect(services.settings[AudioSettings.musicSource] == MusicSource.thisIPad.rawValue)
        services.household.signOut()
        #expect(media.musicSource == .thisIPad)
    }

    @Test func withoutMusicAssistantThereIsNoChoice() async {
        let home = RecordingSmartHome(accessories: [sonos])
        services.smartHome = home
        let media = AudioMediaService(services: services)
        await media.musicAssistant.refreshStatus()
        services.settings[AudioSettings.musicSource] = MusicSource.musicAssistant.rawValue
        #expect(!media.canChooseMusicSource)
        #expect(media.musicSource == .thisIPad, "falls back to the iPad when Music Assistant is gone")
    }

    @Test func playOnSpeakerToolGroupsSetsVolumeAndPlays() async throws {
        let (media, home) = await makeMedia()
        let tool = try #require(AudioAssistantTools.make(media: media).first { $0.name == "play_on_speaker" })
        let answer = try await tool.handler([
            "speaker": "kitchen", "query": "Taylor Swift", "media_type": "playlist", "volume": 30, "also_on": ["office"],
        ])
        #expect(answer == "Playing the playlist This Is Taylor Swift on Kitchen and 1 more.")
        #expect(home.calls.prefix(2) == [
            .join(leader: "media_player.kitchen", members: ["media_player.office_sonos"]),
            .volumeSet(entityID: "media_player.kitchen", level: 0.3),
        ])
        #expect(home.sent.last?.data["service_data"]?["media_type"] == ["playlist"])
        #expect(media.activeKind == nil)
    }

    @Test func unknownSpeakersAreReported() async {
        let (media, _) = await makeMedia()
        #expect(throws: AudioError.speakerNotFound("garage")) { try media.speakerID(named: "garage") }
        await #expect(throws: AudioError.self) { try await media.select(outputID: "ha:media_player.missing") }
        #expect(media.speakerSummary().contains("Bedroom Sonos One, volume 20%, not in Music Assistant"))
    }

    @Test func radioCanPlayOnASpeakerByURL() async throws {
        let (media, home) = await makeMedia()
        let station = try #require(CuratedStations.all.first)
        let answer = try await media.play(station: station, on: sonos.id)
        #expect(answer == "Playing \(station.name) on Bedroom Sonos One.")
        #expect(home.calls == [.playMedia(entityID: "media_player.sonos_one", contentID: station.streamURL.absoluteString)])
        #expect(media.activeKind == nil)
    }
}
