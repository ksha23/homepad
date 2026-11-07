import Foundation
import HomePadCore

/// Transport, volume and the duck for spoken requests. Each goes where
/// `transportTarget` points: a remote speaker, Spotify, or the local source.
/// Seeking makes the service `MediaSeeking`, so the iPhone companion can scrub.
extension AudioMediaService: MediaSeeking {
    public func play() async {
        AppleMusicTrace.note("play")
        switch transportTarget {
        case .remote(let id): await remote { try await $0.transport(.play, on: id) }
        case .local:
            guard let source = activeSource else { return }
            prepareToPlay()
            await perform { try await source.resume() }
        case .spotify: await spotifyPerform { try await $0.resume() }
        case nil: break
        }
    }

    public func pause() async {
        AppleMusicTrace.note("pause")
        switch transportTarget {
        case .remote(let id): await remote { try await $0.transport(.pause, on: id) }
        case .local:
            activeSource?.pause()
            session.releaseSoon()
        case .spotify: await spotifyPerform { try await $0.pause() }
        case nil: break
        }
    }

    func togglePlayPause() async {
        await (nowPlaying?.isPlaying == true ? pause() : play())
    }

    public func nextTrack() async {
        switch transportTarget {
        case .remote(let id): await remote { try await $0.transport(.next, on: id) }
        case .local: await activeSource?.skipForward()
        case .spotify: await spotifyPerform { try await $0.next() }
        case nil: break
        }
    }

    public func previousTrack() async {
        switch transportTarget {
        case .remote(let id): await remote { try await $0.transport(.previous, on: id) }
        case .local: await activeSource?.skipBackward()
        case .spotify: await spotifyPerform { try await $0.previous() }
        case nil: break
        }
    }

    public func seek(to seconds: TimeInterval) async {
        switch transportTarget {
        case .remote(let id): await remote { try await $0.seek(to: seconds, on: id) }
        case .local: activeSource?.seek(to: seconds)
        case .spotify: await spotifyPerform { try await $0.seek(to: seconds) }
        case nil: break
        }
    }

    public func setVolume(_ volume: Double) async {
        let level = max(0, min(1, volume))
        if case .remote(let id) = transportTarget { return await remote { try await $0.setVolume(level, on: id) } }
        if transportTarget == .spotify {
            // Spotify on this iPad plays to the iPad's AirPlay speakers. The Web
            // API refuses volume for phones and tablets.
            guard spotify.playsHere else { return await spotifyPerform { try await $0.setVolume(level) } }
            if spotifyVolume.canSetVolume { return spotifyVolume.set(Float(level)) }
            _ = systemVolume.set(level)
            return
        }
        // Apple's player plays to its own AirPlay speakers, which the system volume does not reach.
        if speakerVolume != nil { return musicVolume.set(Float(level)) }
        if !systemVolume.set(level) { ambient.setVolume(level) }
    }

    /// The AirPlay speakers' volume while Apple's player, or the Spotify app on
    /// this iPad, plays to them, so the iPhone companion and the assistant
    /// change the HomePods, not the iPad. Until Apple's speakers can be read
    /// (right after launch), it is the level the person left them at. The
    /// iPad's own volume, often much higher, was used then, so "turn it down"
    /// could set the HomePods louder.
    public var speakerVolume: Double? {
        if transportTarget == .spotify, spotify.playsHere, spotifyVolume.canSetVolume { return Double(spotifyVolume.volume) }
        guard transportTarget == .local, playsInApplesPlayer else { return nil }
        return musicVolume.level
    }

    /// The current volume level, from 0 to 1.
    public var currentVolume: Double {
        if let speaker = speakerVolume { return speaker }
        return systemVolume.level
    }

    /// True when what is in focus can jump to a position: a song with a known
    /// length can, live radio cannot. The iPhone companion shows a scrubber then.
    public var canSeek: Bool {
        switch transportTarget {
        case .remote: nowPlaying?.duration != nil
        case .spotify: true
        case .local: activeSource?.capabilities.contains(.seek) == true
        case nil: false
        }
    }

    /// True when previous and next work for what is in focus.
    var canSkip: Bool {
        switch transportTarget {
        case .remote, .spotify: true
        case .local: activeSource?.capabilities.contains(.skipForward) == true
        case nil: false
        }
    }

    // MARK: Spoken requests

    /// How loud HomePad's own players stay while the assistant listens and answers.
    static let voiceDuckLevel = 0.2

    /// Lowers this iPad's music while the assistant listens and answers, the way a
    /// HomePod lowers it for Siri, instead of pausing it. Speakers elsewhere in the
    /// house keep playing.
    ///
    /// Apple Music and the library play in Apple's own player, which streams
    /// long-form AirPlay: iPadOS pauses that rather than ducking it. Lowering the
    /// system volume instead was unsafe: the route could change mid-request, and
    /// putting the volume back set the HomePods to the iPad speaker's 80%. So
    /// Apple's player plays on.
    /// Radio and sleep sounds play in HomePad and fade.
    public func duckForVoice() {
        AppleMusicTrace.note("duck for voice: playing \(activeSource?.isPlaying ?? false)")
        guard !isDuckedForVoice, focus == .local, let source = activeSource, source.isPlaying,
              activeKind != .appleMusic, activeKind != .library else { return }
        source.setFadeLevel(Self.voiceDuckLevel)
        isDuckedForVoice = true
    }

    /// Brings HomePad's own players back to full volume after a spoken request.
    /// A sleep timer that is fading keeps its own level.
    public func restoreAfterVoice() async {
        AppleMusicTrace.note("restore after voice: ducked \(isDuckedForVoice), playing \(activeSource?.isPlaying ?? false)")
        guard isDuckedForVoice else { return }
        isDuckedForVoice = false
        if !sleepTimer.isActive { activeSource?.setFadeLevel(1) }
    }
}
