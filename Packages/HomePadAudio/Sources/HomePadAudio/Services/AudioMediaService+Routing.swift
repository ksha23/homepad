import AVFoundation
import HomePadCore

/// Where sound goes: route changes, headphones, the preferred speaker prompt,
/// and selecting outputs.
extension AudioMediaService {
    /// True when AirPods or other headphones are the current output. Other modules
    /// can use the Core helper `AudioRoute.isHeadphonesActive` instead.
    var isHeadphonesActive: Bool { routes.headphonesActive }

    /// Plays on a specific output.
    /// - Remote speakers become the remote target, and Music Assistant speakers also
    ///   become where new music plays. If something plays here, it moves there (radio
    ///   by URL, Apple Music by search through Music Assistant).
    /// - System outputs already in use need nothing. Any other system output opens the
    ///   route picker, because iOS lets only the person choose AirPlay speakers.
    public func select(outputID: AudioOutput.ID) async throws {
        guard let output = outputs.first(where: { $0.id == outputID }) else {
            throw AudioError.speakerNotFound(outputID)
        }
        if output.kind == .homeAssistantPlayer {
            try await moveLocalPlayback(to: outputID)
            remoteTargetID = outputID
            if musicAssistant.player(outputID) != nil { musicAssistant.targetPlayerID = outputID }
            return
        }
        remoteTargetID = nil
        if !routes.outputs.contains(where: { $0.id == outputID }) {
            showRoutePicker()
        }
    }

    /// Re-claims the audio session after "Keep Microphone On" changes, if something plays.
    func applySessionPreference() {
        guard session.claimed != nil else { return }
        session.claim()
    }

    /// Returns transport and volume control to this iPad.
    func controlThisIPad() {
        remoteTargetID = nil
    }

    /// Opens the system AirPlay and Bluetooth picker.
    @discardableResult
    func showRoutePicker() -> Bool {
        routePrompt = nil
        return RoutePickerPresenter.present()
    }

    // MARK: Route changes

    func routeDidChange(from previous: [AudioRoutePort], reason: AVAudioSession.RouteChangeReason) {
        let hadHeadphones = previous.contains(where: \.isHeadphones)
        let hasHeadphones = routes.headphonesActive
        if hadHeadphones != hasHeadphones {
            services.events.post(.custom(name: AudioRoute.headphonesChangedEvent, payload: .bool(hasHeadphones)))
        }
        // Like the Music app: when AirPods drop out, stop instead of blasting the speaker.
        if reason == .oldDeviceUnavailable, hadHeadphones, !hasHeadphones,
           services.settings[AudioSettings.pauseWhenHeadphonesDisconnect] {
            activeSource?.pause()
            session.releaseSoon()
        }
        if routePrompt != nil, !shouldPromptForPreferredSpeaker {
            routePrompt = nil
        }
    }

    /// Call after local playback starts. Offers the preferred speaker when playing elsewhere.
    func playbackStarted() {
        lastError = nil
        routePromptTask?.cancel()
        guard shouldPromptForPreferredSpeaker else {
            routePrompt = nil
            return
        }
        routePrompt = RoutePrompt(speakerName: services.settings[AudioSettings.preferredSpeaker])
        routePromptTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(15))
            guard !Task.isCancelled else { return }
            self?.routePrompt = nil
        }
    }

    private var shouldPromptForPreferredSpeaker: Bool {
        RoutePromptPolicy.shouldPrompt(
            preferredSpeaker: services.settings[AudioSettings.preferredSpeaker],
            enabled: services.settings[AudioSettings.promptForPreferredSpeaker],
            ports: routes.ports
        )
    }

    /// Hands what plays here to a remote speaker, then pauses it here.
    private func moveLocalPlayback(to outputID: AudioOutput.ID) async throws {
        guard remoteTargetID == nil, let source = activeSource, source.isPlaying else { return }
        switch activeKind {
        case .radio:
            guard let station = radio.station else { return }
            try await remotePlayers.playStream(station.streamURL, on: outputID)
        case .appleMusic, .library:
            guard let item = activeSource?.nowPlaying, musicAssistant.player(outputID) != nil else { return }
            let query = [item.title, item.artist].compactMap { $0 }.joined(separator: " ")
            try await musicAssistant.playSearch(query, on: outputID, mediaType: .track)
        default:
            return
        }
        source.pause()
        session.releaseSoon()
    }
}
