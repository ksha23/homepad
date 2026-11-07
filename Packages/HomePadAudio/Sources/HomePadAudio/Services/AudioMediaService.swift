import Foundation
import HomePadCore
import HomePadUI
import Observation

/// HomePad's `MediaService`: one place that knows what plays, where it plays,
/// and how to control it.
///
/// - Local sources play on this iPad, one at a time. Apple Music
///   (`ApplicationMusicPlayer`) and the synced library (`applicationQueuePlayer`)
///   play in Apple's own player, with its own audio session and AirPlay speakers.
///   Internet radio (`AVPlayer`) and sleep sounds (an output-only `AVAudioEngine`)
///   play in HomePad's session and follow its route.
/// - Remote speakers (Music Assistant players, Sonos and other Home Assistant
///   players) play on their own. Transport and volume follow `focus`.
/// - The Music source is a curated choice (`MusicSource`): This iPad, or Music
///   Assistant when Home Assistant has it.
///
/// The rest is in extensions by concern: `+Transport` (transport, volume, the
/// voice duck), `+NowPlaying` (the holds and the system bridge), `+Playback`
/// (starting things), `+Routing` (speakers and route changes) and `+Source`
/// (the music source choice).
@MainActor
@Observable
public final class AudioMediaService: MediaService {
    enum ActiveSource: String { case appleMusic, library, radio, ambient, demo }

    /// What Now Playing shows and transport controls (`+Focus`).
    enum Focus: Equatable {
        case local
        case remote(AudioOutput.ID)
        /// Spotify, on whichever Connect device plays it.
        case spotify
    }

    let appleMusic = AppleMusicPlayer()
    let catalog: AppleMusicCatalog
    let mediaLibrary = MediaLibraryBrowser()
    let libraryPlayer = MediaLibraryPlayer()
    let radio = RadioPlayer()
    let ambient = AmbientSoundPlayer()
    let sleepTimer = SleepTimer()
    /// Shared with the volume sliders, so they show a level set here.
    var systemVolume: SystemVolumeLevel { .shared }
    /// The volume and name of the speakers Apple's player plays to, and the
    /// level the person left each set of speakers at.
    let musicVolume: MusicAirPlayVolume
    /// Apple Music or the library: Apple's own player, with its own AirPlay speakers.
    var playsInApplesPlayer: Bool { activeKind == .appleMusic || activeKind == .library }
    let radioLibrary: RadioLibrary
    let routes: AudioRouteMonitor
    let recognizer: SongRecognizer
    let musicAssistant: MusicAssistantService
    let demo: DemoPlaybackSource?
    /// Spotify through its Web API and Spotify Connect, when turned on in Settings.
    let spotify: SpotifyService
    /// The volume and name of the AirPlay speakers the Spotify app on this iPad
    /// plays to. Spotify's sound follows the iPad's system route, not Apple's
    /// long-form one (`MusicAirPlayVolume.Route`).
    let spotifyVolume = MusicAirPlayVolume(route: .system)
    /// What HomePad tells the person when Spotify cannot play on this iPad yet (`SpotifyWake`).
    var spotifyNotice: SpotifyWake?
    /// Waits for the Spotify app HomePad opened to join Connect, then plays what was asked.
    @ObservationIgnored var spotifyWakeTask: Task<Void, Never>?
    /// The Apple Music library of the account on this iPad, for the Library section.
    let appleMusicLibrary = AppleMusicLibrary()
    /// The recognized member's own Apple Music, linked from their iPhone, shown instead of the iPad's.
    let memberMusic: MemberAppleMusic
    /// Album, playlist and artist pages pushed in the Music app.
    let pages = MusicPageStack()
    /// Where the Music app was left: its section, the Library's kind and the page on top.
    let musicPlace: MusicPlace
    /// Music presents its full-screen player (`NowPlayingView`). Opened by the
    /// mini player and by opening "nowplaying" (the pill, widgets, Control
    /// Center), through `openPlayer()`.
    private(set) var isPlayerOpen = false
    /// The simulator's pretend Home Assistant with Music Assistant, when the demo is on.
    let demoHome: DemoMusicAssistantHome?

    /// The local source in use. Set through `activate(_:)`, and by a switch to another person's saved queue.
    var activeKind: ActiveSource?
    /// A remote speaker the person chose to control directly, ahead of the music source.
    var remoteTargetID: AudioOutput.ID?
    /// The pending "Play on <preferred speaker>?" prompt.
    var routePrompt: RoutePrompt?
    /// Last error worth showing, cleared on the next successful action.
    var lastError: String?
    /// Bumped when a held Now Playing state expires, so screens read it again.
    var holdRevision = 0
    /// True while HomePad's own player is lowered for a spoken request, until
    /// `restoreAfterVoice` brings it back up.
    @ObservationIgnored var isDuckedForVoice = false
    /// Whose queue and place the iPad's player holds (`+Members`).
    @ObservationIgnored var queueOwner: MusicQueueOwner = .household
    /// The member seen last, so only a change of person swaps the queue.
    @ObservationIgnored var lastSeenMemberID: UUID?

    @ObservationIgnored unowned let services: AppServices
    @ObservationIgnored let remotePlayers: RemotePlayerController
    @ObservationIgnored let session: PlaybackSessionClaimer
    @ObservationIgnored var bridge: NowPlayingCenterBridge?
    @ObservationIgnored var routePromptTask: Task<Void, Never>?

    /// Opens Music's full-screen player.
    func openPlayer() {
        guard !isPlayerOpen else { return }
        #if os(iOS)
        FPSMonitor.shared.start(name: "MusicPlayer.expand", duration: 1.2)
        #endif
        isPlayerOpen = true
        AppleMusicTrace.note("player opened")
    }

    /// Closes the player, back to Music as it was.
    func closePlayer() {
        guard isPlayerOpen else { return }
        #if os(iOS)
        FPSMonitor.shared.start(name: "MusicPlayer.collapse", duration: 1.2)
        #endif
        isPlayerOpen = false
        AppleMusicTrace.note("player closed")
    }
    @ObservationIgnored var hold = NowPlayingHold()
    @ObservationIgnored var focusHold = FocusHold()
    @ObservationIgnored var holdTask: Task<Void, Never>?
    @ObservationIgnored var lastBridgeSnapshot: BridgeSnapshot?

    /// - Parameter isDemo: Demo music and speakers, from `-HomePadAudioDemo` (tests pass it).
    init(services: AppServices, isDemo: Bool = AudioDemo.isEnabled) {
        self.services = services
        let demoHome = isDemo ? DemoMusicAssistantHome() : nil
        // Weak, because Music Assistant work can finish after the app's services are gone (in tests).
        let smartHome: @MainActor () -> any SmartHomeService = { [weak services] in
            demoHome ?? services?.smartHome ?? DemoSmartHomeService()
        }
        self.demoHome = demoHome
        catalog = AppleMusicCatalog(isDemo: isDemo)
        radioLibrary = RadioLibrary(settings: services.settings)
        routes = AudioRouteMonitor(demoPorts: isDemo ? AudioDemo.ports : nil)
        recognizer = SongRecognizer(services: services)
        remotePlayers = RemotePlayerController(smartHome: smartHome)
        musicAssistant = MusicAssistantService(settings: services.settings, remote: remotePlayers, smartHome: smartHome)
        spotify = SpotifyService(settings: services.settings, keychain: services.keychain)
        session = PlaybackSessionClaimer(services: services)
        musicPlace = MusicPlace(settings: services.settings)
        memberMusic = MemberAppleMusic(services: services)
        musicVolume = MusicAirPlayVolume(settings: services.settings)
        demo = isDemo ? DemoPlaybackSource(isPlaying: AudioDemo.startsLocalPlayback) : nil
        if demo != nil { activeKind = .demo }
        appleMusic.loadResumePoint(settings: services.settings)
        loadQueueOwner()
        // Apple Music played last: Now Playing shows that song, paused where it
        // stopped, and Play continues it (`AppleMusicPlayer.resume`).
        if activeKind == nil, services.settings[AudioSettings.lastLocalSource] == ActiveSource.appleMusic.rawValue,
           appleMusic.resumePoint != nil {
            activeKind = .appleMusic
        }
        AudioDemo.applyLaunchSource(to: services.settings)
        spotify.isSelected = { [weak self] in self?.musicSource == .spotify }
        wireSpotify()
        wireMemberAccounts()
        pages.onTopChange = { [musicPlace] page in musicPlace.save(page: page) }
    }

    /// Wires remote commands, route changes, the sleep timer and Music Assistant. Called once after launch.
    func start() {
        bridge = NowPlayingCenterBridge(handlers: .init(
            play: { [weak self] in await self?.play() },
            pause: { [weak self] in await self?.pause() },
            togglePlayPause: { [weak self] in await self?.togglePlayPause() },
            next: { [weak self] in await self?.nextTrack() },
            previous: { [weak self] in await self?.previousTrack() },
            seek: { [weak self] seconds in Task { await self?.seek(to: seconds) } }
        ))
        routes.onChange = { [weak self] previous, reason in self?.routeDidChange(from: previous, reason: reason) }
        sleepTimer.onFade = { [weak self] level in self?.activeSource?.setFadeLevel(level) }
        sleepTimer.onExpire = { [weak self] in self?.stopAll() }
        musicAssistant.start()
        let volumeTrace = DebugTrace(file: "audio-session-trace.txt", argument: "HomePadAudioTrace")
        musicVolume.onLog = { text in volumeTrace.log("music volume \(text)") }
        spotifyVolume.onLog = { text in volumeTrace.log("spotify route volume \(text)") }
        musicVolume.isMusicPlaying = { [weak self] in
            guard let self else { return false }
            return self.playsInApplesPlayer && self.activeSource?.isPlaying == true
        }
        musicVolume.startUpdating()
        trackNowPlaying()
        appleMusic.onQueueChange = { [weak self] in self?.saveOwnerState() }
        trackQueueOwner()
        memberMusic.start()
        trackMemberAccounts()
        if musicSource == .spotify { Task { await refreshSpotify() } }
        refreshSpotifyWhenActive()
        if AudioDemo.showsSongCard { recognizer.showDemo(AudioDemo.song) }
        if let interval = AudioDemo.skipEvery {
            Task { [weak self] in
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(interval))
                    guard let self else { return }
                    await self.nextTrack()
                }
            }
        }
    }

    var activeSource: (any PlaybackSource)? {
        switch activeKind {
        case .appleMusic: appleMusic
        case .library: libraryPlayer
        case .radio: radio
        case .ambient: ambient
        case .demo: demo
        case nil: nil
        }
    }

    // MARK: MediaService

    /// Now Playing for every surface (pill, Control Center, widget, Now Playing app),
    /// held steady through track changes by `NowPlayingHold`.
    public var nowPlaying: NowPlaying? {
        _ = holdRevision
        return hold.resolve(liveNowPlaying, at: Date())
    }

    public var outputs: [AudioOutput] {
        routes.outputs + remotePlayers.outputs.map { output in
            var output = output
            if output.id == remoteTargetID { output.isActive = true }
            return output
        }
    }

    /// Where the music in focus plays, when HomePad can tell. Apple's player picks
    /// its own AirPlay speakers, so for Apple Music and the library this is their
    /// name from `musicVolume`: HomePad's own route ("iPad") was shown while the
    /// HomePods played.
    var musicOutputName: String? {
        if transportTarget == .spotify { return spotifyOutputName }
        if case .remote(let id) = transportTarget, let output = outputs.first(where: { $0.id == id }) { return output.name }
        return playsInApplesPlayer ? musicVolume.speakerName : routes.currentRouteName
    }

    /// A label for where music plays: "Speakers" when HomePad cannot tell.
    public var currentRouteName: String { musicOutputName ?? "Speakers" }

    // MARK: Lifecycle helpers

    /// Makes `kind` the active local source, stopping the previous one and claiming the session.
    func activate(_ kind: ActiveSource) {
        AppleMusicTrace.note("activate \(kind)")
        if activeKind != kind { activeSource?.stop() }
        activeKind = kind
        if kind != .demo { services.settings[AudioSettings.lastLocalSource] = kind.rawValue }
        remoteTargetID = nil
        prepareToPlay()
    }

    /// Claims the session and undoes a finished sleep timer's fade, which would otherwise leave the source silent.
    ///
    /// Apple Music and the music library play in Apple's own player, which has
    /// its own audio session and AirPlay route, so HomePad claims nothing for
    /// them. A claim made HomePad's session one that does not mix, and the
    /// player starting then interrupted it, which silenced the microphone and the
    /// wake word for as long as the music played.
    func prepareToPlay() {
        if activeKind == .appleMusic || activeKind == .library {
            session.release()
        } else {
            session.claim()
        }
        if !sleepTimer.isActive { activeSource?.setFadeLevel(1) }
    }

    /// Stops all local playback (sleep timer end, "stop").
    func stopAll() {
        activeSource?.stop()
        activeKind = nil
        sleepTimer.cancel()
        session.release()
    }

    /// Runs a remote speaker command and keeps the error for the UI.
    func remote(_ action: (RemotePlayerController) async throws -> Void) async {
        await perform { try await action(remotePlayers) }
    }

    /// Runs a UI action and keeps its error for display.
    func perform(_ action: () async throws -> Void) async {
        do {
            try await action()
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }
}
