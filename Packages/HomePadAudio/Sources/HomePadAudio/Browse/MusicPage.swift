import Foundation
import MusicKit
import Observation

/// A page pushed inside the Music app: an album, playlist or artist, from
/// Apple Music, the simulator demo or Spotify.
enum MusicPage: Hashable, Identifiable {
    case appleMusicAlbum(Album)
    case appleMusicPlaylist(Playlist)
    case appleMusicArtist(Artist)
    /// A demo album, playlist or artist, by its Music Assistant style item.
    case demo(MAMediaItem)
    case spotify(SpotifyItem)
    /// One of the recognized member's own playlists, read with their token.
    case memberPlaylist(MemberMusicItem)

    var id: String {
        switch self {
        case .memberPlaylist(let item): "member:playlist:\(item.id)"
        case .appleMusicAlbum(let album): "am:album:\(album.id.rawValue)"
        case .appleMusicPlaylist(let playlist): "am:playlist:\(playlist.id.rawValue)"
        case .appleMusicArtist(let artist): "am:artist:\(artist.id.rawValue)"
        case .demo(let item): "demo:\(item.uri)"
        case .spotify(let item): "spotify:\(item.uri)"
        }
    }

    var title: String {
        switch self {
        case .appleMusicAlbum(let album): album.title
        case .appleMusicPlaylist(let playlist): playlist.name
        case .appleMusicArtist(let artist): artist.name
        case .demo(let item): item.name
        case .spotify(let item): item.name
        case .memberPlaylist(let item): item.title
        }
    }
}

/// The pages pushed in the Music app, newest last. Kept by the media service,
/// so tiles built anywhere (shelves, search, the Library) can open a page.
@MainActor
@Observable
final class MusicPageStack {
    private(set) var pages: [MusicPage] = []
    /// Told the page on top after every change, so `MusicPlace` can save it.
    @ObservationIgnored var onTopChange: ((MusicPage?) -> Void)?

    var top: MusicPage? { pages.last }

    func push(_ page: MusicPage) {
        guard page != pages.last else { return }
        pages.append(page)
        onTopChange?(top)
    }

    func pop() {
        _ = pages.popLast()
        onTopChange?(top)
    }

    func popToRoot() {
        guard !pages.isEmpty else { return }
        pages.removeAll()
        onTopChange?(nil)
    }
}
