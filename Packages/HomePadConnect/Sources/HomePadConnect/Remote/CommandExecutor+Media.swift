import Foundation
import HomePadCore

// Music commands, through `services.media` only, so they work whatever the
// Audio module does inside. Every value from the other device is checked first.
extension CommandExecutor {
    func execute(_ command: MediaCommand) async throws -> String? {
        let media = services.media
        switch command {
        case .play:
            await media.play()
        case .pause:
            await media.pause()
        case .nextTrack:
            await media.nextTrack()
        case .previousTrack:
            await media.previousTrack()
        case .seek(let seconds):
            guard seconds.isFinite, seconds >= 0 else { throw RemoteCommandError.badNumber }
            let seeking = media as? any MediaSeeking
            RemoteMediaTrace.trace.log("seek to \(Int(seconds)) s from a remote, can seek \(seeking?.canSeek == true), "
                                       + "now at \(media.nowPlaying?.elapsed.map { Int($0) } ?? -1) s")
            guard let seeking, seeking.canSeek else { throw RemoteCommandError.cannotSeek }
            await seeking.seek(to: seconds)
        case .setVolume(let level):
            guard level.isFinite else { throw RemoteCommandError.badNumber }
            await media.setVolume(min(1, max(0, level)))
        case .selectOutput(let id):
            guard let output = media.outputs.first(where: { $0.id == id }) else { throw RemoteCommandError.unknownSpeaker }
            try await media.select(outputID: output.id)
        case .playSearch(let query):
            let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { throw RemoteCommandError.emptySearch }
            guard text.count <= MediaCommand.maxQueryLength else { throw RemoteCommandError.searchTooLong }
            let started = try await media.playSearch(text)
            return "Playing \(started)."
        }
        return nil
    }
}

/// `-HomePadAudioTrace YES` also writes Documents/remote-trace.txt: each seek a phone or Mac sends,
/// whether this HomePad could seek, and where playback was, to tell a seek that never arrived from one
/// the player did not take. On a phone the same file holds the scrubber's side: each drag, the seek it
/// sent or why it sent none, and each status while the bar holds a seek.
@MainActor
enum RemoteMediaTrace {
    static let trace = DebugTrace(file: "remote-trace.txt", argument: "HomePadAudioTrace")
}
