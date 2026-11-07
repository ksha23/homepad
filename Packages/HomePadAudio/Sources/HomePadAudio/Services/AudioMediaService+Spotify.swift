import AVFoundation
import Foundation
import HomePadCore
import UIKit

/// Spotify as the music source: playing, queueing, waking the Spotify app on
/// this iPad, and the error the screens show.
extension AudioMediaService {
    /// How long HomePad waits for the Spotify app it opened to join Connect,
    /// and keeps the music that was asked for. Long enough to look around in
    /// Spotify before coming back.
    static let spotifyWakeLifetime: TimeInterval = 120

    /// Gives the Spotify service what only the media service knows.
    func wireSpotify() {
        spotify.homePadPlays = { [weak self] in self?.activeSource?.isPlaying == true }
        // True while an app with audio that does not mix plays here. Spotify's does not.
        spotify.otherAppPlaysHere = { AVAudioSession.sharedInstance().secondaryAudioShouldBeSilencedHint }
    }

    /// Reads Spotify again each time HomePad comes back to the front, such as
    /// from the Spotify app, so a device that just joined and what it plays show at once.
    func refreshSpotifyWhenActive() {
        NotificationCenter.default.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.spotify.isEnabled, self.spotify.isReady else { return }
                Task { await self.refreshSpotify() }
            }
        }
    }

    /// Runs a Spotify command and keeps its error for the screens.
    func spotifyPerform(_ action: (SpotifyService) async throws -> Void) async {
        do {
            try await action(spotify)
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }

    /// Reads Spotify's devices, what plays, and Listen Now, when Spotify becomes
    /// the source or the Music app opens on it.
    func refreshSpotify() async {
        guard spotify.isReady else { return }
        spotifyVolume.startUpdating()
        async let devices: Void = spotify.refreshDevices()
        async let playback: Void = spotify.refreshPlayback()
        _ = await (devices, playback)
        if !spotify.hasLoadedHome, spotify.isReady { await spotify.loadHome() }
        spotify.startPolling()
    }

    /// Plays a Spotify item on the chosen Connect device. In an album or
    /// playlist (`context`), the rest of it follows.
    func playSpotify(_ item: SpotifyItem, in context: SpotifyItem? = nil) async {
        await playSpotify(uri: item.uri, in: context?.uri, recent: (context ?? item).recent)
    }

    /// Plays on the target device. When that is this iPad and Spotify is not
    /// open here, HomePad opens it and plays once it is up, or says why it cannot.
    func playSpotify(uri: String, in context: String? = nil, recent: RecentMusicItem?) async {
        await useSpotifyAccountForNewMusic()
        do {
            try await spotify.play(uri: uri, in: context)
            lastError = nil
        } catch SpotifyError.notOpenHere {
            wakeSpotifyHere { [weak self] in await self?.playSpotify(uri: uri, in: context, recent: recent) }
            return
        } catch {
            lastError = error.localizedDescription
            return
        }
        // Two things never play at once: what this iPad played pauses.
        if activeSource?.isPlaying == true {
            activeSource?.pause()
            session.releaseSoon()
        }
        noteRecent(recent)
    }

    /// Adds a track to Spotify's queue, after the current one.
    func addToSpotifyQueue(_ item: SpotifyItem) async {
        await spotifyPerform { try await $0.addToQueue(uri: item.uri) }
    }

    // MARK: Waking Spotify on this iPad

    /// Opens the Spotify app here so it joins Spotify Connect, then runs `then`
    /// once it has. Guided Access blocks opening another app, and HomePad says
    /// so instead (`spotifyNotice`).
    func wakeSpotifyHere(then: (@MainActor () async -> Void)? = nil) {
        let advice = SpotifyWake.advice(isInstalled: SpotifyLinks.isInstalled, isGuidedAccess: UIAccessibility.isGuidedAccessEnabled)
        guard advice == .openSpotify else {
            spotifyNotice = advice
            return
        }
        spotify.beginWake()
        SpotifyLinks.openApp()
        spotifyWakeTask?.cancel()
        spotifyWakeTask = Task { [weak self] in
            await self?.waitForSpotifyHere()
            guard let self, !Task.isCancelled else { return }
            self.spotify.endWake()
            if self.spotify.thisIPad != nil {
                await then?()
            } else {
                self.spotifyNotice = self.spotify.thisIPadIsOthers.map(SpotifyWake.signedInAsOther) ?? .notIdentified
            }
        }
    }

    /// Reads the device list every two seconds until the Spotify app here is
    /// in it. When iPadOS keeps HomePad running while Spotify is in front, the
    /// music starts before the person comes back. Otherwise it starts once
    /// HomePad is back.
    private func waitForSpotifyHere() async {
        let deadline = Date().addingTimeInterval(Self.spotifyWakeLifetime)
        repeat {
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            await spotify.refreshDevices()
            if spotify.thisIPad != nil { return }
        } while Date() < deadline
    }

    /// The name of where Spotify plays now: the AirPlay speakers when it plays
    /// on this iPad, else the Connect device.
    var spotifyOutputName: String? {
        if spotify.playsHere { return spotifyVolume.speakerName ?? "This iPad" }
        return spotify.playback?.device?.name ?? spotify.targetDevice?.name
    }
}
