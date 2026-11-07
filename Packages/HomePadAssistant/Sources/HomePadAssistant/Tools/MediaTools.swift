import Foundation
import HomePadCore

/// Music playback through `services.media`.
enum MediaTools {
    static func make(_ context: ToolContext) -> [AssistantTool] {
        [play(context), control(context), volume(context)]
    }

    static func play(_ context: ToolContext) -> AssistantTool {
        AssistantTool(
            name: "play_music",
            description: "Search for and play music: a song, artist, album, playlist, genre or mood. "
                + "For an open request such as \"play some music\", pick a genre or mood that fits the moment.",
            parameters: Schema.object(["query": Schema.string("What to play, for example \"jazz for cooking\".")], required: ["query"])
        ) { json in
            let query = try ToolArguments(json).requireString("query")
            let started = try await context.services.media.playSearch(query)
            return "Now playing \(started)."
        }
    }

    static func control(_ context: ToolContext) -> AssistantTool {
        AssistantTool(
            name: "media_control",
            description: "Pause, resume or skip what is playing on HomePad.",
            parameters: Schema.object(["action": Schema.string("What to do.", enumValues: ["play", "pause", "next", "previous"])], required: ["action"])
        ) { json in
            let media = try context.services.media
            let before = media.nowPlaying
            let action = try ToolArguments(json).requireString("action")
            switch action {
            case "play": await media.play()
            case "pause": await media.pause()
            case "next": await media.nextTrack()
            case "previous": await media.previousTrack()
            default: throw ToolError("Unknown media action.")
            }
            return describe(action, await settled(media, after: action, from: before))
        }
    }

    /// What is playing once the player has caught up with the command, waiting up
    /// to 1.5 s. Read at once, a pause came back as "Now playing Swan Lake", and
    /// the model told the person the pause had not worked although it had.
    @MainActor
    static func settled(_ media: any MediaService, after action: String, from before: NowPlaying?) async -> NowPlaying? {
        for _ in 0..<15 {
            let now = media.nowPlaying
            switch action {
            case "pause": if now?.isPlaying != true { return now }
            case "play": if now?.isPlaying == true { return now }
            default: if now?.title != before?.title { return now }
            }
            try? await Task.sleep(for: .milliseconds(100))
        }
        return media.nowPlaying
    }

    /// The result of a media command in words that cannot be misread as the opposite.
    static func describe(_ action: String, _ state: NowPlaying?) -> String {
        guard let state else { return action == "pause" ? "Paused." : "Nothing is playing." }
        let item = state.title + (state.artist.map { " by \($0)" } ?? "")
        switch (action, state.isPlaying) {
        case ("pause", true): return "Asked the player to pause, but it still reports \(item) as playing."
        case (_, true): return "Playing \(item)."
        case ("pause", false): return "Paused \(item)."
        default: return "\(item) is paused."
        }
    }

    static func volume(_ context: ToolContext) -> AssistantTool {
        AssistantTool(
            name: "set_volume",
            description: "Set HomePad's music volume. "
                + "When asked to turn volume up or down without a specific number, adjust mildly by 5% to 10% (e.g. change: 7 or change: -7). "
                + "Provide 'change' for relative adjustments (+5 to +10 for mild up, -5 to -10 for mild down, +20 to +30 for way up), "
                + "or 'level' for an exact target (0 to 100).",
            parameters: Schema.object([
                "level": Schema.number("Target volume from 0 to 100. Optional if change is provided."),
                "change": Schema.number("Relative volume change in percent (e.g. +7, -10, +25). Use this for 'turn it up', 'turn it down', 'turn it way up', etc."),
            ])
        ) { json in
            let args = ToolArguments(json)
            let media = try context.services.media
            let current = media.currentVolume
            let target: Double
            if let change = args.double("change") {
                target = max(0, min(1, current + (change / 100.0)))
            } else if let level = args.double("level") {
                target = DeviceCommandMapper.percent(level)
            } else {
                // If neither given, default to mild +7%
                target = max(0, min(1, current + 0.07))
            }
            await media.setVolume(target)
            return "Volume set to \(Int((target * 100).rounded()))%."
        }
    }
}
