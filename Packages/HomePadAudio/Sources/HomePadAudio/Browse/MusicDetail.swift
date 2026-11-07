import Foundation

/// An album, playlist or artist page from any source, ready to draw: a header
/// with Play, Shuffle and a More menu, a track list, and shelves (an artist's albums).
struct MusicDetail {
    enum Kind {
        case album, playlist, artist

        var title: String {
            switch self {
            case .album: "Album"
            case .playlist: "Playlist"
            case .artist: "Artist"
            }
        }
    }

    /// One row of the track list.
    struct Track: Identifiable {
        let item: MusicTileItem
        /// The album's track number. Nil in playlists and top songs, which show artwork.
        var number: Int?
        var duration: TimeInterval?

        var id: String { item.id }
        var durationText: String? { duration.map(PlaybackScrubber.format) }
    }

    let kind: Kind
    let title: String
    /// The artist of an album, the curator of a playlist.
    var subtitle: String?
    /// "12 Songs, 2021", or a playlist's description.
    var detail: String?
    /// The artwork, and what a tap on it does.
    let header: MusicTileItem
    var tracksTitle: String?
    var tracks: [Track] = []
    var shelves: [MusicShelfModel] = []
    /// Play, Shuffle, Play Next, Play Later and Add to Library for the whole page.
    var actions = MusicItemMenu()

    /// "12 Songs, 48 Minutes".
    static func summary(songCount: Int, duration: TimeInterval?) -> String {
        var parts = [songCount == 1 ? "1 Song" : "\(songCount) Songs"]
        if let duration, duration >= 60 {
            let minutes = Int((duration / 60).rounded())
            if minutes >= 60 {
                parts.append(minutes % 60 == 0 ? "\(minutes / 60) Hr" : "\(minutes / 60) Hr \(minutes % 60) Min")
            } else {
                parts.append("\(minutes) Min")
            }
        }
        return parts.joined(separator: ", ")
    }
}
