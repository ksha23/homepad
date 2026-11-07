import Foundation
import HomePadCore

/// Assistant tools owned by the Audio module. The generic play_music,
/// media_control and set_volume tools come from the Assistant module and call
/// `services.media`, so they are not repeated here.
@MainActor
enum AudioAssistantTools {
    static func make(media: AudioMediaService) -> [AssistantTool] {
        [playRadio(media), playSleepSounds(media), identifySong(media), listSpeakers(media), playOnSpeaker(media)]
    }

    private static func playRadio(_ media: AudioMediaService) -> AssistantTool {
        AssistantTool(
            name: "play_radio",
            description: "Play an internet radio station on this iPad's speakers, or on a home speaker. Finds stations by name or genre, for example \"KEXP\", \"groove salad\" or \"jazz\".",
            parameters: Schema.object([
                "station": Schema.string("Station name, genre, or a stream URL."),
                "speaker": Schema.string("Optional home speaker to play on instead of this iPad, for example \"kitchen HomePod\"."),
            ], required: ["station"])
        ) { arguments in
            let query = arguments["station"]?.stringValue ?? ""
            let station: RadioStation
            if let url = URL(string: query), url.scheme?.lowercased().hasPrefix("http") == true, url.host() != nil {
                station = .custom(name: url.host() ?? "Stream", url: url)
            } else if let found = await media.radioLibrary.bestStation(for: query) {
                station = found
            } else {
                throw AudioError.nothingFound(query)
            }
            let speakerID = try arguments["speaker"]?.stringValue.map(media.speakerID(named:))
            return try await media.play(station: station, on: speakerID)
        }
    }

    private static func playSleepSounds(_ media: AudioMediaService) -> AssistantTool {
        AssistantTool(
            name: "play_sleep_sounds",
            description: "Play a calming generated sound for sleep or focus, with an optional sleep timer.",
            parameters: Schema.object([
                "sound": Schema.string("Which sound.", enumValues: AmbientSound.allCases.map(\.rawValue)),
                "minutes": Schema.integer("Stop after this many minutes. 0 means no timer. Omit to use the default timer."),
            ], required: ["sound"])
        ) { arguments in
            let sound = AmbientSound(rawValue: arguments["sound"]?.stringValue?.lowercased() ?? "") ?? .rain
            let minutes = arguments["minutes"]?.intValue
            try media.playSleepSound(sound, minutes: minutes)
            var answer = "Playing \(sound.title) on \(media.currentRouteName)."
            if let remaining = media.sleepTimer.remaining() {
                answer += " It stops in \(Int((remaining / 60).rounded())) minutes."
            }
            return answer
        }
    }

    private static func identifySong(_ media: AudioMediaService) -> AssistantTool {
        AssistantTool(
            name: "identify_song",
            description: "Listen for about 15 seconds through the microphone and identify the song playing nearby, like Shazam."
        ) { _ in
            switch await media.recognizer.identify() {
            case .success(let match): "That's \(match.spokenDescription)."
            case .failure(let error): error.errorDescription ?? "I couldn't recognize that song."
            }
        }
    }

    private static func listSpeakers(_ media: AudioMediaService) -> AssistantTool {
        AssistantTool(
            name: "list_speakers",
            description: "List where audio can play: this iPad's current output (AirPlay, AirPods, built-in) and home speakers that can play by themselves. AirPlay speakers can only be chosen by the person in the AirPlay menu, which this tool can open.",
            parameters: Schema.object([
                "show_airplay_menu": Schema.boolean("Also open the AirPlay menu on screen so the person can pick speakers or AirPods."),
            ])
        ) { arguments in
            if arguments["show_airplay_menu"]?.boolValue == true { media.showRoutePicker() }
            return media.speakerSummary()
        }
    }

    private static func playOnSpeaker(_ media: AudioMediaService) -> AssistantTool {
        AssistantTool(
            name: "play_on_speaker",
            description: "Play music on a home speaker (HomePod, Sonos or a group) through Music Assistant, without moving this iPad's audio. Searches Apple Music, Spotify, radio and the library, for example \"Taylor Swift in the kitchen\". Can also set the volume and group other speakers with it.",
            parameters: Schema.object([
                "speaker": Schema.string("The speaker, for example \"kitchen\" or \"living room HomePods\"."),
                "query": Schema.string("What to play, for example \"Taylor Swift\" or \"dinner party playlist\". Omit to resume."),
                "media_type": Schema.string("Optional kind of thing to search for.",
                                            enumValues: ["track", "album", "artist", "playlist", "radio"]),
                "volume": Schema.number("Optional volume from 0 to 100."),
                "also_on": [
                    "type": "array", "items": ["type": "string"],
                    "description": "Other speakers that should play the same thing, for multi-room.",
                ],
            ], required: ["speaker"])
        ) { arguments in
            let speakerID = try media.speakerID(named: arguments["speaker"]?.stringValue ?? "")
            let name = media.outputs.first { $0.id == speakerID }?.name ?? "the speaker"
            let others = try (arguments["also_on"]?.arrayValue ?? []).compactMap(\.stringValue).map(media.speakerID(named:))
            if !others.isEmpty { try await media.remotePlayers.group(leader: speakerID, members: others) }
            if let volume = arguments["volume"]?.doubleValue {
                try await media.remotePlayers.setVolume(volume > 1 ? volume / 100 : volume, on: speakerID)
            }
            guard let query = arguments["query"]?.stringValue, !query.isEmpty else {
                try await media.remotePlayers.transport(.play, on: speakerID)
                media.remoteTargetID = speakerID
                return "Resumed \(name)."
            }
            guard media.musicAssistant.player(speakerID) != nil else { throw AudioError.musicAssistantUnavailable }
            let type = arguments["media_type"]?.stringValue.flatMap(MAMediaItem.MediaType.init(rawValue:))
            let started = try await media.musicAssistant.playSearch(query, on: speakerID, mediaType: type)
            media.remoteTargetID = media.musicSource == .musicAssistant ? nil : speakerID
            return others.isEmpty ? "Playing \(started)." : "Playing \(started) and \(others.count) more."
        }
    }
}

extension AudioMediaService {
    /// The ID of the home speaker someone named, or `speakerNotFound`.
    func speakerID(named name: String) throws -> AudioOutput.ID {
        let speakers = outputs.filter { $0.kind == .homeAssistantPlayer }
        guard let match = RemotePlayerMapper.find(name, in: speakers) else { throw AudioError.speakerNotFound(name) }
        return match.id
    }

    /// A plain-text list of outputs for the assistant.
    func speakerSummary() -> String {
        var lines = ["This iPad plays on \(routes.currentRouteName)."]
        if isHeadphonesActive { lines.append("Headphones are connected, so playback is private.") }
        if routes.multipleRoutesDetected && !routes.isAirPlayActive {
            lines.append("AirPlay speakers are nearby. The person can choose them in the AirPlay menu.")
        }
        let speakers = outputs.filter { $0.kind == .homeAssistantPlayer }
        if speakers.isEmpty {
            lines.append("No home speakers are available through Home Assistant.")
        } else {
            lines.append("Home speakers that can play on their own:")
            for speaker in speakers {
                var line = "- \(speaker.name)"
                if let playing = remotePlayers.nowPlaying(on: speaker.id) { line += ", playing \(playing.title)" }
                if let volume = speaker.volume { line += ", volume \(Int(volume * 100))%" }
                if let player = musicAssistant.player(speaker.id) {
                    let group = musicAssistant.groupMembers(of: player).map(\.name)
                    if !group.isEmpty { line += ", grouped with \(group.formatted(.list(type: .and)))" }
                } else {
                    line += ", not in Music Assistant, so it can't search for music"
                }
                lines.append(line)
            }
            lines.append("The music source is \(musicSource.title).")
        }
        return lines.joined(separator: "\n")
    }
}
