import Foundation
import HomePadCore
import MusicKit

/// A trace of what MusicKit reports and what Now Playing shows, for finding
/// skip glitches on a device. Launching with `-HomePadAudioTrace YES` appends a
/// line per change to Documents/audio-trace.txt, which
/// `xcrun devicectl device copy from --domain-type appDataContainer` fetches.
@MainActor
enum AppleMusicTrace {
    private static let trace = DebugTrace(file: "audio-trace.txt", argument: "HomePadAudioTrace")
    static var isEnabled: Bool { trace.isEnabled }

    /// The player's current entry and state, logged only when something besides the time changed.
    static func player(_ player: ApplicationMusicPlayer) {
        guard isEnabled else { return }
        let entry = player.queue.currentEntry
        let item: String
        var album = "-"
        var itemArt = "-"
        switch entry?.item {
        case .song(let song):
            item = "song"
            album = song.albumTitle ?? "-"
            itemArt = name(song.artwork)
        case .musicVideo: item = "video"
        case nil: item = "nil"
        @unknown default: item = "other"
        }
        let line = "player entry=\(entry?.id.suffix(8) ?? "none") transient=\(entry?.isTransient ?? false) item=\(item) "
            + "title=\(entry?.title ?? "-") album=\(album) art=\(name(entry?.artwork)) songArt=\(itemArt) status=\(player.state.playbackStatus)"
        trace.logIfChanged("player", line)
    }

    /// Anything else worth a line, such as the cover Now Playing switched to.
    static func note(_ text: @autoclosure () -> String) {
        trace.log(text())
    }

    /// A short name for an artwork: its scheme and the end of its image URL.
    static func name(_ artwork: Artwork?) -> String {
        guard let url = artwork?.url(width: 100, height: 100) else { return "none" }
        let tail = url.pathComponents.suffix(3).map { String($0.suffix(20)) }.joined(separator: "/")
        return "\(url.scheme ?? "?"):\(tail)"
    }
}
