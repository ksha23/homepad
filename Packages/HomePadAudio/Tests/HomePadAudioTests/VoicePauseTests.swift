import Foundation
import HomePadCore
import Testing
@testable import HomePadAudio

/// Music on the iPad lowers while the assistant listens and answers, as a
/// HomePod lowers it for Siri, and comes back up after. It never pauses.
@MainActor @Suite struct VoicePauseTests {
    /// The media service holds `AppServices` unowned, so the suite keeps it.
    private let services = AppServices(settings: SettingsStore(defaults: UserDefaults(suiteName: "audio.voice.\(UUID())")!))

    private func makePlayingMedia() -> AudioMediaService {
        let media = AudioMediaService(services: services, isDemo: true)
        services.media = media
        #expect(media.activeSource?.isPlaying == true, "the demo starts playing on this iPad")
        return media
    }

    @Test func musicKeepsPlayingLowerDuringAQuestion() async {
        let media = makePlayingMedia()
        media.duckForVoice()
        #expect(media.activeSource?.isPlaying == true)
        #expect(media.isDuckedForVoice)
        await media.restoreAfterVoice()
        #expect(media.activeSource?.isPlaying == true)
        #expect(media.isDuckedForVoice == false)
    }

    @Test func pauseTheMusicStaysPaused() async {
        let media = makePlayingMedia()
        media.duckForVoice()
        await media.pause()
        await media.restoreAfterVoice()
        #expect(media.activeSource?.isPlaying == false)
        #expect(media.isDuckedForVoice == false)
    }

    @Test func nextSongEndsWithMusicPlaying() async {
        let media = makePlayingMedia()
        media.duckForVoice()
        await media.nextTrack()
        await media.restoreAfterVoice()
        #expect(media.activeSource?.isPlaying == true)
        #expect(media.isDuckedForVoice == false)
    }

    @Test func nothingDucksWhenNothingWasPlaying() async {
        let media = makePlayingMedia()
        await media.pause()
        media.duckForVoice()
        #expect(media.isDuckedForVoice == false)
    }
}
