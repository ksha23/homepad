import Foundation
import HomePadCore
import Testing
@testable import HomePadAudio

/// The full-screen player and the Now Playing widget set the volume of the
/// same thing, the one transport goes to (`NowPlayingVolumeTarget`).
@MainActor @Suite struct NowPlayingVolumeTargetTests {
    /// The media service holds `AppServices` unowned, as the app keeps both alive, so the suite keeps it too.
    private let services = AppServices(settings: SettingsStore(defaults: UserDefaults(suiteName: "audio.volumeTarget.\(UUID())")!))

    private func makeMedia() async -> AudioMediaService {
        services.smartHome = RecordingSmartHome.withMusicAssistant([Speakers.kitchen, Speakers.office])
        let media = AudioMediaService(services: services, isDemo: false)
        services.media = media
        await media.musicAssistant.refreshStatus()
        return media
    }

    @Test func nothingLoadedSetsTheSystemVolume() async {
        let media = await makeMedia()
        #expect(media.volumeTarget == .system)
        #expect(media.volumeTarget.showsAirPlayButton)
    }

    @Test func aChosenSpeakerSetsThatSpeaker() async throws {
        let media = await makeMedia()
        try await media.select(outputID: Speakers.kitchen.id)
        #expect(media.volumeTarget == .remote(Speakers.kitchen.id))
        #expect(!media.volumeTarget.showsAirPlayButton, "Music Assistant speakers are picked in Play On, not AirPlay")
    }

    @Test func applesPlayerSetsItsSpeakersNotTheSystemVolume() async {
        let media = await makeMedia()
        media.activeKind = .appleMusic
        // Speakers that take a level get it. Speakers that read but refuse one are this iPad, set by the
        // system volume. Only speakers HomePad cannot read at all leave the AirPlay menu.
        let volume = media.musicVolume
        let expected: NowPlayingVolumeTarget = volume.canSetVolume ? .appleMusicSpeakers
            : volume.speakerName == nil ? .airPlayMenu : .system
        #expect(media.volumeTarget == expected)
    }
}
