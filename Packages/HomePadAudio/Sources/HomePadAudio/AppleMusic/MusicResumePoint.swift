import Foundation
import MusicKit

/// Where Apple Music playback was, saved so a restart continues the same song at
/// the same moment in the same album, playlist or song list. Without it HomePad
/// came back offering the last album, which then played from its first track.
struct MusicResumePoint: Codable, Equatable, Sendable {
    /// What the queue was built from, by MusicKit id.
    enum Container: Codable, Equatable, Sendable {
        case album(String)
        case playlist(String)
        case station(String)
        /// Songs from a search or a recognized song, in queue order.
        case songs([String])

        /// "album", "playlist", "station" or "songs", for the audio trace.
        var kind: String {
            switch self {
            case .album: "album"
            case .playlist: "playlist"
            case .station: "station"
            case .songs: "songs"
            }
        }
    }

    var container: Container
    /// The song that was playing.
    var songID: String?
    /// What Now Playing shows before playback starts again.
    var title: String
    var artist: String?
    var album: String?
    var artwork: Artwork?
    var duration: TimeInterval?
    /// The song's place in the queue, for when its id is not found again.
    var index: Int?
    /// Seconds into the song.
    var position: TimeInterval
    var savedAt: Date

    /// Where a rebuilt queue starts: the saved song if it is still there, else
    /// its old place, else the beginning.
    static func startIndex(songIDs: [String], songID: String?, savedIndex: Int?) -> Int {
        if let songID, let found = songIDs.firstIndex(of: songID) { return found }
        if let savedIndex, songIDs.indices.contains(savedIndex) { return savedIndex }
        return 0
    }

    /// Where the song continues: two seconds before it stopped, so the moment is
    /// recognizable, and from the top when it had nearly ended.
    static func resumePosition(_ position: TimeInterval, duration: TimeInterval?) -> TimeInterval {
        if let duration, duration > 0, position > duration - 5 { return 0 }
        return max(0, position - 2)
    }

    /// True when a new save is worth writing: another song, playing or paused
    /// changed, or the position moved on by `interval` seconds.
    static func needsSaving(_ new: MusicResumePoint, after old: MusicResumePoint?, interval: TimeInterval = 10) -> Bool {
        guard let old else { return true }
        if old.songID != new.songID || old.container != new.container || old.title != new.title { return true }
        return abs(new.position - old.position) >= interval
    }
}
