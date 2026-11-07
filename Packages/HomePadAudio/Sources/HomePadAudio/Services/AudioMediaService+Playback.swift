import Foundation
import HomePadCore
import MusicKit
import UIKit

/// Starting things: spoken searches, Apple Music, the library, radio and sleep sounds.
extension AudioMediaService {
    /// Search and play, from the assistant's `play_music` tool and anywhere else.
    /// - A speaker named in the request ("in the kitchen") or chosen to control plays
    ///   it through Music Assistant.
    /// - With Music Assistant as the source, it plays on the chosen speaker.
    /// - With Spotify as the source, it plays Spotify's best match on the chosen device.
    /// - On This iPad it tries Apple Music, then the synced library, then radio.
    public func playSearch(_ query: String) async throws -> String {
        let speakers = outputs.filter { $0.kind == .homeAssistantPlayer }
        let request = SpokenMusicRequest(query, speakers: speakers)
        if let speakerID = request.speakerID ?? remoteTargetID {
            guard musicAssistant.player(speakerID) != nil else { throw AudioError.musicAssistantUnavailable }
            let started = try await musicAssistant.playSearch(request.query, on: speakerID)
            remoteTargetID = musicSource == .musicAssistant ? nil : speakerID
            return started
        }
        switch musicSource {
        case .musicAssistant: return try await musicAssistant.playSearch(request.query)
        case .spotify where spotify.isReady: return try await playSearchOnSpotify(request.query)
        default: return try await playSearchOnThisIPad(request.query)
        }
    }

    /// Spotify's best match: an artist named exactly, else the first song, album or playlist.
    func playSearchOnSpotify(_ query: String) async throws -> String {
        // Searched in the account of whoever asked.
        await useSpotifyAccountForNewMusic()
        await spotify.search(query)
        guard let results = spotify.searchResults else { throw AudioError.nothingFound(query) }
        let lowered = query.lowercased()
        let exactArtist = results.artists.first { $0.name.caseInsensitiveCompare(query) == .orderedSame }
        let best = (lowered.contains("playlist") ? results.playlists.first : nil)
            ?? (lowered.contains("album") ? results.albums.first : nil)
            ?? exactArtist ?? results.tracks.first ?? results.albums.first ?? results.playlists.first
        guard let best else { throw AudioError.nothingFound(query) }
        let title = best.subtitle.map { "“\(best.name)” by \($0)" } ?? best.name
        do {
            try await spotify.play(uri: best.uri)
        } catch SpotifyError.notOpenHere {
            // Outside Guided Access HomePad can open Spotify here and play once it is up.
            let advice = SpotifyWake.advice(isInstalled: SpotifyLinks.isInstalled, isGuidedAccess: UIAccessibility.isGuidedAccessEnabled)
            guard advice == .openSpotify else { throw SpotifyError.notOpenHere }
            wakeSpotifyHere { [weak self] in await self?.playSpotify(best) }
            return "Opening Spotify for \(title)"
        }
        noteRecent(best.recent)
        return "\(title) on \(playbackDestinationName)"
    }

    /// Apple Music when the catalog works, then the synced library, then internet radio,
    /// so "play jazz" still works for guests and without a subscription.
    func playSearchOnThisIPad(_ query: String) async throws -> String {
        // "Play my playlist Road Trip" looks in the recognized person's own library first.
        if let started = try await playFromMemberLibrary(query) { return started }
        if await appleMusic.requestAuthorization(), appleMusic.canPlayCatalog,
           let choice = try? await AppleMusicCatalog.bestChoice(for: query) {
            try await play(choice)
            return choice.title
        }
        if await mediaLibrary.requestAuthorization() {
            mediaLibrary.load()
            if let entry = mediaLibrary.bestMatch(for: query) {
                try await playLibrary(entry)
                return entry.title
            }
        }
        if let station = await radioLibrary.bestStation(for: query) {
            try await play(station: station)
            return "\(station.name) radio"
        }
        throw AudioError.nothingFound(query)
    }

    /// Plays a playlist, album or artist from the synced library.
    func playLibrary(_ entry: MediaLibraryBrowser.Entry) async throws {
        activate(.library)
        try await libraryPlayer.play(entry.collection)
        playbackStarted()
    }

    /// Plays a Music Assistant item on the chosen speaker and keeps errors for the UI.
    func playOnMusicAssistant(_ item: MAMediaItem) async {
        await perform { try await musicAssistant.play(item) }
    }

    /// Plays the song ShazamKit found, when it is in the Apple Music catalog.
    func play(_ match: SongMatch) async throws {
        guard let id = match.appleMusicID else { throw AudioError.nothingFound(match.title) }
        let request = MusicCatalogResourceRequest<Song>(matching: \.id, equalTo: MusicItemID(id))
        guard let song = try await request.response().items.first else { throw AudioError.nothingFound(match.title) }
        try await play(.songs([song], start: song))
    }

    /// Plays a station here, or on a remote speaker when `outputID` names one.
    @discardableResult
    func play(station: RadioStation, on outputID: AudioOutput.ID? = nil) async throws -> String {
        if let outputID, let speaker = outputs.first(where: { $0.id == outputID }), speaker.kind == .homeAssistantPlayer {
            try await remotePlayers.playStream(station.streamURL, on: outputID)
            radioLibrary.notePlayed(station)
            return "Playing \(station.name) on \(speaker.name)."
        }
        activate(.radio)
        try await radio.play(station)
        radioLibrary.notePlayed(station)
        playbackStarted()
        return "Playing \(station.name)."
    }

    /// Starts a sleep sound with the default sleep timer unless `minutes` says otherwise (0 means no timer).
    func playSleepSound(_ sound: AmbientSound, volume: Double? = nil, title: String? = nil, minutes: Int? = nil) throws {
        activate(.ambient)
        try ambient.play(sound, volume: volume ?? ambient.volume, title: title)
        sleepTimer.start(minutes: minutes ?? services.settings[AudioSettings.defaultSleepTimerMinutes])
        playbackStarted()
    }

    func play(_ preset: SleepPreset) throws {
        try playSleepSound(preset.sound, volume: preset.volume, title: preset.title, minutes: preset.timerMinutes)
    }
}
