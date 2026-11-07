import Foundation
import HomePadCore
import Testing
@testable import HomePadAudio

/// After a restart HomePad offered the last album and played it from its first
/// track. It now continues the same song at the same moment.
@MainActor @Suite struct MusicResumeTests {
    private func point(song: String? = "s3", index: Int? = 2, position: TimeInterval = 95, duration: TimeInterval? = 240) -> MusicResumePoint {
        MusicResumePoint(container: .album("1440"), songID: song, title: "Third Song", artist: "Artist", album: "Album",
                         artwork: nil, duration: duration, index: index, position: position, savedAt: Date(timeIntervalSince1970: 0))
    }

    @Test func restoreStartsAtTheSavedSong() {
        let ids = ["s1", "s2", "s3", "s4"]
        #expect(MusicResumePoint.startIndex(songIDs: ids, songID: "s3", savedIndex: 0) == 2)
        // The song is gone from the playlist: its old place, then the start.
        #expect(MusicResumePoint.startIndex(songIDs: ids, songID: "gone", savedIndex: 1) == 1)
        #expect(MusicResumePoint.startIndex(songIDs: ids, songID: "gone", savedIndex: 9) == 0)
        #expect(MusicResumePoint.startIndex(songIDs: [], songID: "s3", savedIndex: 2) == 0)
    }

    @Test func restoreRewindsALittleAndStartsOverNearTheEnd() {
        #expect(MusicResumePoint.resumePosition(95, duration: 240) == 93)
        #expect(MusicResumePoint.resumePosition(1, duration: 240) == 0)
        #expect(MusicResumePoint.resumePosition(237, duration: 240) == 0)
        #expect(MusicResumePoint.resumePosition(95, duration: nil) == 93)
    }

    @Test func savesOnSongChangesAndEveryTenSeconds() {
        let saved = point()
        #expect(MusicResumePoint.needsSaving(saved, after: nil))
        var later = saved
        later.position += 4
        #expect(!MusicResumePoint.needsSaving(later, after: saved))
        later.position += 6
        #expect(MusicResumePoint.needsSaving(later, after: saved))
        var next = saved
        next.songID = "s4"
        next.title = "Fourth Song"
        #expect(MusicResumePoint.needsSaving(next, after: saved))
    }

    @Test func survivesBeingSavedAndRead() throws {
        let settings = SettingsStore(defaults: UserDefaults(suiteName: "audio.resume.\(UUID())")!)
        settings[AudioSettings.appleMusicResume] = point()
        #expect(settings[AudioSettings.appleMusicResume] == point())
        let songs = MusicResumePoint(container: .songs(["a", "b"]), songID: "b", title: "B", artist: nil, album: nil, artwork: nil,
                                     duration: nil, index: 1, position: 12, savedAt: Date(timeIntervalSince1970: 0))
        let data = try JSONEncoder().encode(songs)
        #expect(try JSONDecoder().decode(MusicResumePoint.self, from: data) == songs)
    }

    /// When Apple Music played last, launch shows that song, paused where it stopped.
    @Test func launchShowsTheSavedSongWhenAppleMusicPlayedLast() {
        let settings = SettingsStore(defaults: UserDefaults(suiteName: "audio.resume.launch.\(UUID())")!)
        settings[AudioSettings.appleMusicResume] = point()
        settings[AudioSettings.lastLocalSource] = "appleMusic"
        let services = AppServices(settings: settings)
        let media = AudioMediaService(services: services, isDemo: false)
        #expect(media.activeKind == .appleMusic)
        #expect(media.appleMusic.nowPlaying?.title == "Third Song")
        #expect(media.appleMusic.nowPlaying?.isPlaying == false)
        #expect(media.appleMusic.nowPlaying?.elapsed == 95)
        withExtendedLifetime(services) {}
    }

    @Test func launchOffersNothingWhenRadioPlayedLast() {
        let settings = SettingsStore(defaults: UserDefaults(suiteName: "audio.resume.radio.\(UUID())")!)
        settings[AudioSettings.appleMusicResume] = point()
        settings[AudioSettings.lastLocalSource] = "radio"
        let services = AppServices(settings: settings)
        let media = AudioMediaService(services: services, isDemo: false)
        #expect(media.activeKind == nil)
        withExtendedLifetime(services) {}
    }
}
