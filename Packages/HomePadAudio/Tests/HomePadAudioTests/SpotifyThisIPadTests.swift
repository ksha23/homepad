import Foundation
import HomePadCore
import Testing
@testable import HomePadAudio

/// Spotify on this iPad: which Connect device is the Spotify app here, what
/// HomePad does when it is not open, where the speaker button goes, what the
/// volume moves, and which setup step comes next.
@MainActor @Suite struct SpotifyThisIPadTests {
    private func device(_ id: String, _ type: String = "Tablet", active: Bool = false) -> SpotifyDevice {
        let json = try? JSONValue.parse(#"{"id":"\#(id)","name":"\#(id)","type":"\#(type)","is_active":\#(active)}"#)
        return SpotifyDevice(json: json)!
    }

    private func seen(_ devices: [SpotifyDevice], remembered: String? = nil, playing: SpotifyDevice? = nil,
                      otherApp: Bool = false, homePad: Bool = false, before: Set<String>? = nil) -> SpotifyThisIPad.Observation {
        .init(devices: devices, remembered: remembered, playing: playing, otherAppPlaysHere: otherApp,
              homePadPlays: homePad, listedBeforeWake: before)
    }

    // MARK: Which device is this iPad

    /// A device that joins while HomePad has Spotify open here is this iPad.
    @Test func aDeviceThatJoinsDuringAWakeIsThisIPad() {
        let phone = device("phone", "Smartphone"), here = device("here")
        #expect(SpotifyThisIPad.identify(seen([phone, here], before: ["phone"])) == "here")
        // Two join at once: the tablet is this iPad's kind.
        let speaker = device("speaker", "Speaker")
        #expect(SpotifyThisIPad.identify(seen([phone, speaker, here], before: ["phone"])) == "here")
        // Nothing new: HomePad cannot tell.
        #expect(SpotifyThisIPad.identify(seen([phone, here], before: ["phone", "here"])) == nil)
    }

    /// A tablet that plays while another app's audio plays here is this iPad,
    /// unless HomePad's own player is what plays.
    @Test func aTabletPlayingWhileThisIPadHearsAnotherAppIsThisIPad() {
        let here = device("here", active: true)
        #expect(SpotifyThisIPad.identify(seen([here], playing: here, otherApp: true)) == "here")
        #expect(SpotifyThisIPad.identify(seen([here], playing: here, otherApp: false)) == nil)
        #expect(SpotifyThisIPad.identify(seen([here], playing: here, otherApp: true, homePad: true)) == nil)
        let phone = device("phone", "Smartphone", active: true)
        #expect(SpotifyThisIPad.identify(seen([phone], playing: phone, otherApp: true)) == nil, "phones are never this iPad")
    }

    /// Another iPad playing Spotify never takes the place of the one learned.
    @Test func aRememberedDeviceThatIsListedStays() {
        let here = device("here"), other = device("other", active: true)
        #expect(SpotifyThisIPad.identify(seen([here, other], remembered: "here", playing: other, otherApp: true)) == "here")
        #expect(SpotifyThisIPad.identify(seen([here, other], remembered: "here", before: ["other"])) == "here")
        // Asleep: the remembered ID stays, and the device is just not listed.
        #expect(SpotifyThisIPad.identify(seen([other], remembered: "here")) == "here")
    }

    @Test func theServiceLearnsAndKeepsThisIPadOnThisIPadOnly() async {
        let settings = SettingsStore(defaults: UserDefaults(suiteName: "audio.spotify.here.\(UUID())")!)
        settings[SpotifyAccountOwner.household.recordKey] = SpotifyAccountRecord()
        let services = AppServices(settings: settings)
        let media = AudioMediaService(services: services, isDemo: false)
        let spotify = media.spotify
        #expect(spotify.hereState == .unknown)
        let here = device("here", active: true)
        spotify.devices = [here]
        spotify.playback = SpotifyPlayback(json: (try? JSONValue.parse(
            #"{"is_playing":true,"device":{"id":"here","name":"iPad","type":"Tablet","is_active":true}}"#)) ?? .null)
        spotify.otherAppPlaysHere = { true }
        spotify.learnThisIPad()
        #expect(spotify.thisIPadID == "here")
        #expect(settings[SpotifyAccountOwner.household.recordKey]?.thisIPadID == "here", "kept with the household's account, on this iPad")
        #expect(spotify.hereState == .open)
        #expect(spotify.playsHere)
        // The Spotify app here went to sleep and left the list.
        spotify.devices = []
        spotify.playback = nil
        spotify.learnThisIPad()
        #expect(spotify.hereState == .notOpen)
        #expect(spotify.thisIPadID == "here")
        withExtendedLifetime(services) {}
    }

    // MARK: Spotify not open here

    @Test func newMusicForThisIPadNeedsSpotifyOpenHere() async {
        let services = AppServices(settings: SettingsStore(defaults: UserDefaults(suiteName: "audio.spotify.play.\(UUID())")!))
        let media = AudioMediaService(services: services, isDemo: false)
        await #expect(throws: SpotifyError.notOpenHere) { try await media.spotify.play(uri: "spotify:album:a1") }
        withExtendedLifetime(services) {}
    }

    /// Guided Access blocks opening another app, so HomePad says how instead of trying.
    @Test func wakeAdviceFollowsGuidedAccessAndTheApp() {
        #expect(SpotifyWake.advice(isInstalled: true, isGuidedAccess: false) == .openSpotify)
        #expect(SpotifyWake.advice(isInstalled: true, isGuidedAccess: true) == .leaveGuidedAccess)
        #expect(SpotifyWake.advice(isInstalled: false, isGuidedAccess: false) == .installSpotify)
        #expect(SpotifyWake.leaveGuidedAccess.message.contains("Triple-click"))
    }

    // MARK: Speakers and volume

    /// Spotify on this iPad picks its speakers in AirPlay, as Apple Music does.
    /// Another Spotify device is picked in Play On.
    @Test func theSpeakerButtonOpensAirPlayForSpotifyHere() {
        let settings = SettingsStore(defaults: UserDefaults(suiteName: "audio.spotify.route.\(UUID())")!)
        settings[SpotifyAccountOwner.household.recordKey] = SpotifyAccountRecord()
        let services = AppServices(settings: settings)
        let media = AudioMediaService(services: services, isDemo: false)
        settings[AudioSettings.spotifyEnabled] = true
        media.setMusicSource(.spotify)
        #expect(media.spotify.targetsThisIPad, "this iPad is the default")
        #expect(media.newMusicUsesAirPlay)
        media.spotify.accounts.update(.household) { $0.deviceID = "kitchen" }
        #expect(!media.newMusicUsesAirPlay)
        #expect(!media.spotify.playsHere)
        withExtendedLifetime(services) {}
    }

    /// The slider moves the speakers when AirPlay takes a level, the system
    /// volume when the route is this iPad, and the AirPlay menu otherwise.
    @Test func spotifyHereSetsItsAirPlaySpeakers() {
        #expect(NowPlayingVolumeTarget.airPlay(.spotifySpeakers, canSetVolume: true, speakerName: "Back Stereo Pair") == .spotifySpeakers)
        #expect(NowPlayingVolumeTarget.airPlay(.spotifySpeakers, canSetVolume: false, speakerName: "iPad") == .system)
        #expect(NowPlayingVolumeTarget.airPlay(.spotifySpeakers, canSetVolume: false, speakerName: nil) == .airPlayMenu)
        #expect(NowPlayingVolumeTarget.spotifySpeakers.showsAirPlayButton)
        #expect(!NowPlayingVolumeTarget.spotify.showsAirPlayButton, "other Spotify devices are picked in Play On")
    }

    // MARK: Setup

    @Test func setupPointsAtTheStepThatFixesTheState() {
        typealias Step = SpotifySetupStep
        #expect(Step.next(status: .needsClientID, here: .unknown) == .createApp)
        #expect(Step.next(status: .signedOut, here: .unknown) == .signIn)
        #expect(Step.next(status: .problem(.notAllowed), here: .unknown) == .addAccounts)
        #expect(Step.next(status: .problem(.invalidClientID), here: .unknown) == .pasteClientID)
        #expect(Step.next(status: .problem(.signInExpired), here: .open) == .signIn)
        #expect(Step.next(status: .ready, here: .unknown) == .openSpotify)
        #expect(Step.next(status: .ready, here: .notOpen) == nil, "asleep later is not a setup step")
    }
}
