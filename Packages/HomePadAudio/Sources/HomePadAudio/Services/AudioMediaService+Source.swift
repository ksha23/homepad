import Foundation
import HomePadCore

/// The music source choice: This iPad, Music Assistant or Spotify.
extension AudioMediaService {
    /// What the person picked: their own choice while they use HomePad, else the household's.
    var preferredMusicSource: MusicSource {
        if let member = services.household.activeMember,
           let raw = member.preferences[AudioSettings.musicSourcePreference]?.stringValue,
           let source = MusicSource(rawValue: raw) {
            return source
        }
        return MusicSource(rawValue: services.settings[AudioSettings.musicSource]) ?? .thisIPad
    }

    /// The source in use. Music Assistant only counts while Home Assistant has it
    /// running, and Spotify while it is turned on in Settings with an account
    /// for whoever uses HomePad (`SpotifyService.isOffered`), so HomePad falls
    /// back to This iPad on its own.
    var musicSource: MusicSource {
        switch preferredMusicSource {
        case .musicAssistant: musicAssistant.isReady ? .musicAssistant : .thisIPad
        case .spotify: spotify.isOffered ? .spotify : .thisIPad
        case .thisIPad: .thisIPad
        }
    }

    /// The sources there is a choice of right now.
    var availableMusicSources: [MusicSource] {
        MusicSource.allCases.filter { source in
            switch source {
            case .thisIPad: true
            case .musicAssistant: musicAssistant.isReady
            case .spotify: spotify.isOffered
            }
        }
    }

    /// The switch shows only when there is a choice to make.
    var canChooseMusicSource: Bool { availableMusicSources.count > 1 }

    /// Remembers the choice for the person using HomePad, or for the household when nobody is recognized.
    func setMusicSource(_ source: MusicSource) {
        if var member = services.household.activeMember {
            member.preferences[AudioSettings.musicSourcePreference] = .string(source.rawValue)
            services.household.update(member)
        } else {
            services.settings[AudioSettings.musicSource] = source.rawValue
        }
        remoteTargetID = nil
        pages.popToRoot()
        switch source {
        case .musicAssistant:
            if musicAssistant.isReady, musicAssistant.home.isEmpty { Task { await musicAssistant.loadHome() } }
        case .spotify:
            Task { await refreshSpotify() }
        case .thisIPad:
            break
        }
    }

    /// The name of where new music plays, for headers and buttons.
    var playbackDestinationName: String {
        switch musicSource {
        case .musicAssistant:
            guard let target = musicAssistant.targetPlayer else { return "No Speaker" }
            let others = musicAssistant.groupMembers(of: target).count
            return others == 0 ? target.name : "\(target.name) + \(others)"
        case .spotify:
            if spotify.targetsThisIPad { return spotifyVolume.speakerName ?? "This iPad" }
            return spotify.targetDevice?.name ?? "No Device"
        case .thisIPad:
            return musicOutputName ?? "This iPad"
        }
    }

    /// True when the speaker button for new music opens Apple's AirPlay picker:
    /// new music comes out of this iPad, through Apple's player or the Spotify
    /// app here. Music Assistant speakers and other Spotify devices are not
    /// AirPlay, so they get the Play On panel.
    var newMusicUsesAirPlay: Bool {
        switch musicSource {
        case .thisIPad: true
        case .spotify: spotify.targetsThisIPad
        case .musicAssistant: false
        }
    }

    /// True when what plays now comes out of this iPad, so its speakers are picked in AirPlay.
    var nowPlayingUsesAirPlay: Bool {
        switch focus {
        case .local: true
        case .spotify: spotify.playsHere
        case .remote, nil: false
        }
    }

    /// Music Assistant players that play while this iPad is the source, for "Elsewhere in the House".
    var elsewhereInTheHouse: [MusicAssistantPlayer] {
        guard musicSource == .thisIPad else { return [] }
        return musicAssistant.players.filter { $0.isPlaying && !$0.followsGroup }
    }
}
