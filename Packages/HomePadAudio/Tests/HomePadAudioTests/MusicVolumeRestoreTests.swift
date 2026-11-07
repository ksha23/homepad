import Foundation
import HomePadCore
import Testing
@testable import HomePadAudio

/// The music volume after a restart and a reconnect: the speakers' own reading
/// wins, the person's last level fills in while they cannot be read, and the
/// only write puts that exact level back when speakers come up louder.
@Suite struct MusicVolumeRestoreTests {
    typealias Reading = MusicVolumeRestore.Reading

    private let back = "Back Stereo Pair"
    private let kitchen = "Kitchen"
    private let start = Date(timeIntervalSince1970: 1_000_000)

    private func memory(_ levels: [(String, Double)]) -> MusicVolumeMemory {
        var memory = MusicVolumeMemory()
        // Oldest first, so the first pair ends up newest.
        for (speakers, level) in levels.reversed() { memory.remember(level, for: speakers) }
        return memory
    }

    private func reading(_ speakers: String?, _ level: Double, playing: Bool = true, canSet: Bool = true) -> Reading {
        Reading(speakers: speakers, level: level, canSet: canSet, isPlaying: playing)
    }

    // MARK: Memory

    @Test func speakersAreOneKeyWhateverTheOrder() {
        #expect(MusicVolumeMemory.speakers(names: ["Kitchen", "Back Stereo Pair"]) == "Back Stereo Pair + Kitchen")
        #expect(MusicVolumeMemory.speakers(names: ["Back Stereo Pair", "Kitchen", "Kitchen"]) == "Back Stereo Pair + Kitchen")
        #expect(MusicVolumeMemory.speakers(names: ["Speaker"]) == "iPad")
        #expect(MusicVolumeMemory.speakers(names: []) == nil)
    }

    @Test func memoryKeepsOneLevelPerSpeakersNewestFirst() {
        var memory = MusicVolumeMemory()
        memory.remember(0.25, for: back)
        memory.remember(0.6, for: kitchen)
        memory.remember(0.3, for: back)
        #expect(memory.entries.map(\.speakers) == [back, kitchen])
        #expect(memory.level(for: back) == 0.3)
        #expect(memory.level(for: kitchen) == 0.6)
        #expect(memory.lastLevel == 0.3)
        memory.remember(1.4, for: kitchen)
        #expect(memory.level(for: kitchen) == 1)
        for index in 0..<20 { memory.remember(0.5, for: "Speaker \(index)") }
        #expect(memory.entries.count == MusicVolumeMemory.capacity)
        #expect(memory.level(for: back) == nil)
    }

    @MainActor @Test func memorySurvivesARestart() {
        let settings = SettingsStore(defaults: UserDefaults(suiteName: "audio.volume.\(UUID())")!)
        settings[AudioSettings.musicVolumes] = memory([(back, 0.25), (kitchen, 0.6)])
        #expect(settings[AudioSettings.musicVolumes].level(for: back) == 0.25)
        #expect(settings[AudioSettings.musicVolumes].lastSpeakers == back)
    }

    // MARK: What shows at launch

    @Test func theSpeakersOwnReadingWinsAndNothingIsWritten() {
        var restore = MusicVolumeRestore(memory: memory([(back, 0.25)]))
        let idle = reading(back, 0.4, playing: false)
        #expect(restore.handle(idle, at: start) == .none)
        #expect(restore.shownLevel(idle) == 0.4)
        #expect(restore.memory.level(for: back) == 0.25, "a reading while nothing plays is not remembered")
    }

    @Test func unreadableSpeakersShowTheLastLevelNotTheIPads() {
        let restore = MusicVolumeRestore(memory: memory([(back, 0.25), (kitchen, 0.6)]))
        #expect(restore.shownLevel(reading(nil, 0, playing: false, canSet: false)) == 0.25)
        #expect(MusicVolumeRestore(memory: MusicVolumeMemory()).shownLevel(reading(nil, 0, canSet: false)) == nil)
    }

    @Test func unreadableNamedSpeakersShowTheirOwnLevel() {
        var restore = MusicVolumeRestore(memory: memory([(back, 0.25), (kitchen, 0.6)]))
        let named = reading(kitchen, 0, playing: false, canSet: false)
        #expect(restore.handle(named, at: start) == .none)
        #expect(restore.shownLevel(named) == 0.6)
    }

    // MARK: The first playback after a launch

    @Test func louderSpeakersGetThePersonsLevelBack() {
        var restore = MusicVolumeRestore(memory: memory([(back, 0.25)]))
        #expect(restore.handle(reading(back, 0.25, playing: false), at: start) == .none)
        #expect(restore.handle(reading(back, 0.25), at: start.addingTimeInterval(1)) == .none)
        #expect(restore.handle(reading(back, 0.6), at: start.addingTimeInterval(2)) == .restore(0.25))
        #expect(restore.memory.level(for: back) == 0.25)
    }

    @Test func quieterSpeakersAreLeftAloneAndRemembered() {
        var restore = MusicVolumeRestore(memory: memory([(back, 0.25)]))
        #expect(restore.handle(reading(back, 0.1), at: start) == .none)
        #expect(restore.handle(reading(back, 0.1), at: start.addingTimeInterval(9)) == .none)
        #expect(restore.memory.level(for: back) == 0.1)
    }

    @Test func aSmallDifferenceIsTheSameLevel() {
        var restore = MusicVolumeRestore(memory: memory([(back, 0.25)]))
        #expect(restore.handle(reading(back, 0.27), at: start) == .none)
        #expect(restore.handle(reading(back, 0.27), at: start.addingTimeInterval(9)) == .none)
        #expect(restore.memory.level(for: back) == 0.25, "the person's exact level is kept")
    }

    @Test func speakersNeverSetAreLeftAlone() {
        var restore = MusicVolumeRestore(memory: memory([(kitchen, 0.2)]))
        #expect(restore.handle(reading(back, 0.7), at: start) == .none)
        #expect(restore.handle(reading(back, 0.7), at: start.addingTimeInterval(9)) == .none)
        #expect(restore.memory.level(for: back) == 0.7)
    }

    @Test func thePersonsOwnChoiceStopsTheRestore() {
        var restore = MusicVolumeRestore(memory: memory([(back, 0.25)]))
        #expect(restore.handle(reading(back, 0.25), at: start) == .none)
        restore.personChose(0.7)
        #expect(restore.handle(reading(back, 0.7), at: start.addingTimeInterval(2)) == .none)
        #expect(restore.memory.level(for: back) == 0.7)
    }

    @Test func aLevelChosenBeforePlayingIsTheOneRestored() {
        var restore = MusicVolumeRestore(memory: memory([(back, 0.25)]))
        #expect(restore.handle(reading(back, 0.25, playing: false), at: start) == .none)
        restore.personChose(0.15)
        #expect(restore.handle(reading(back, 0.5), at: start.addingTimeInterval(3)) == .restore(0.15))
    }

    @Test func itGivesUpAfterTwoTries() {
        var restore = MusicVolumeRestore(memory: memory([(back, 0.25)]))
        #expect(restore.handle(reading(back, 0.6), at: start) == .restore(0.25))
        #expect(restore.handle(reading(back, 0.6), at: start.addingTimeInterval(2)) == .restore(0.25))
        #expect(restore.handle(reading(back, 0.6), at: start.addingTimeInterval(4)) == .none)
    }

    @Test func nothingIsRestoredUntilTheMusicPlays() {
        var restore = MusicVolumeRestore(memory: memory([(back, 0.25)]))
        #expect(restore.handle(reading(back, 0.6, playing: false), at: start) == .none)
        #expect(restore.handle(reading(back, 0.6, playing: false), at: start.addingTimeInterval(20)) == .none)
        #expect(restore.handle(reading(back, 0.6), at: start.addingTimeInterval(30)) == .restore(0.25))
    }

    // MARK: After the first seconds

    @Test func aVolumeChangedElsewhereIsRememberedNotUndone() {
        var restore = MusicVolumeRestore(memory: memory([(back, 0.25)]))
        #expect(restore.handle(reading(back, 0.25), at: start) == .none)
        #expect(restore.handle(reading(back, 0.25), at: start.addingTimeInterval(9)) == .none)
        #expect(restore.handle(reading(back, 0.5), at: start.addingTimeInterval(30)) == .none)
        #expect(restore.memory.level(for: back) == 0.5)
    }

    @Test func aPauseIsNotAReconnect() {
        var restore = MusicVolumeRestore(memory: memory([(back, 0.25)]))
        #expect(restore.handle(reading(back, 0.25), at: start) == .none)
        #expect(restore.handle(reading(back, 0.25, playing: false), at: start.addingTimeInterval(60)) == .none)
        #expect(restore.handle(reading(back, 0.5), at: start.addingTimeInterval(120)) == .none)
        #expect(restore.memory.level(for: back) == 0.5)
    }

    // MARK: Per speaker

    @Test func eachSpeakerComesBackToItsOwnLevel() {
        var restore = MusicVolumeRestore(memory: memory([(back, 0.25), (kitchen, 0.6)]))
        #expect(restore.handle(reading(kitchen, 0.6), at: start) == .none)
        #expect(restore.handle(reading(back, 0.6), at: start.addingTimeInterval(20)) == .restore(0.25))
    }

    @Test func aReconnectToTheSameSpeakersRestoresAgain() {
        var restore = MusicVolumeRestore(memory: memory([(back, 0.25)]))
        #expect(restore.handle(reading(back, 0.25), at: start) == .none)
        #expect(restore.handle(reading(back, 0.25), at: start.addingTimeInterval(20)) == .none)
        #expect(restore.handle(reading(nil, 0, canSet: false), at: start.addingTimeInterval(30)) == .none)
        #expect(restore.handle(reading(back, 0.7), at: start.addingTimeInterval(40)) == .restore(0.25))
    }

    @Test func aChoiceIsRememberedForTheSpeakersInUse() {
        var restore = MusicVolumeRestore(memory: memory([(back, 0.25), (kitchen, 0.6)]))
        _ = restore.handle(reading(kitchen, 0.6), at: start)
        restore.personChose(0.4)
        #expect(restore.memory.level(for: kitchen) == 0.4)
        #expect(restore.memory.level(for: back) == 0.25)
    }

    // MARK: The media service at launch

    /// Apple Music is the source after a restart and its speakers have not
    /// answered yet: the volume the assistant and the iPhone remote use is the
    /// one the person left the HomePods at, not the iPad's own.
    @MainActor @Test func launchVolumeIsThePersonsLastNotTheIPads() async {
        let settings = SettingsStore(defaults: UserDefaults(suiteName: "audio.volume.\(UUID())")!)
        settings[AudioSettings.musicVolumes] = memory([(back, 0.25)])
        let services = AppServices(settings: settings)
        let media = AudioMediaService(services: services, isDemo: false)
        services.media = media
        media.activeKind = .appleMusic
        #expect(media.speakerVolume == 0.25)
        #expect(media.currentVolume == 0.25)
        // The speakers take a Float, so 0.2 comes back as 0.2000000030.
        await media.setVolume(0.2)
        #expect(abs(media.currentVolume - 0.2) < 0.0001)
        #expect(abs((media.musicVolume.rememberedLevel ?? 0) - 0.2) < 0.0001)
        // The media service holds its services unowned.
        withExtendedLifetime(services) {}
    }
}
