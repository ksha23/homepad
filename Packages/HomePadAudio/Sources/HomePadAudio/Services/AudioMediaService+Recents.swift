import Foundation
import HomePadCore
import MusicKit

/// Playing and opening what the person using HomePad played lately.
extension AudioMediaService {
    /// Plays a Recently Played item again, from its source.
    func playRecent(_ item: RecentMusicItem) async {
        switch item.source {
        case .demo:
            playDemo(matching: item.title)
        case .spotify:
            await playSpotify(uri: item.itemID, recent: item)
        case .memberLibrary:
            await playMemberRecent(item)
        case .appleMusic:
            if item.kind == .artist {
                guard let artist = try? await AppleMusicLookup.artist(MusicItemID(item.itemID)) else {
                    lastError = AudioError.nothingFound(item.title).localizedDescription
                    return
                }
                return await playArtist(artist)
            }
            await perform {
                guard let playable = try await Self.appleMusicItem(item) else { throw AudioError.nothingFound(item.title) }
                try await startAppleMusic(recent: item) { try await appleMusic.play(mixed: [playable]) }
            }
        }
    }

    /// Opens the page of a Recently Played album, playlist or artist.
    func openRecent(_ item: RecentMusicItem) async {
        switch item.source {
        case .demo:
            let type: MAMediaItem.MediaType = item.kind == .playlist ? .playlist : item.kind == .artist ? .artist : .album
            if let found = DemoMusicCatalog.items(of: type).first(where: { $0.name == item.title }) { pages.push(.demo(found)) }
        case .spotify:
            if let page = SpotifyItem(recent: item) { pages.push(.spotify(page)) }
        case .memberLibrary:
            openMemberRecent(item)
        case .appleMusic:
            let id = MusicItemID(item.itemID)
            switch item.kind {
            case .album: if let album = try? await AppleMusicLookup.album(id) { pages.push(.appleMusicAlbum(album)) }
            case .playlist: if let playlist = try? await AppleMusicLookup.playlist(id) { pages.push(.appleMusicPlaylist(playlist)) }
            case .artist: if let artist = try? await AppleMusicLookup.artist(id) { pages.push(.appleMusicArtist(artist)) }
            case .song: if let song = try? await AppleMusicLookup.song(id) { await openAlbum(of: song) }
            case .station: break
            }
        }
    }

    private static func appleMusicItem(_ item: RecentMusicItem) async throws -> (any PlayableMusicItem)? {
        let id = MusicItemID(item.itemID)
        switch item.kind {
        case .album: return try await AppleMusicLookup.album(id)
        case .playlist: return try await AppleMusicLookup.playlist(id)
        case .station: return try await AppleMusicLookup.station(id, title: item.title)
        case .song: return try await AppleMusicLookup.song(id)
        case .artist: return nil
        }
    }
}

extension MusicShelves {
    /// A Recently Played tile: a tap plays it again, and its menu opens its page.
    static func recentTile(_ item: RecentMusicItem, _ media: AudioMediaService) -> MusicTileItem {
        var menu = MusicItemMenu()
        if item.kind != .station {
            menu.open = { Task { await media.openRecent(item) } }
            menu.openTitle = switch item.kind {
            case .artist: "Show Artist"
            case .playlist: "Show Playlist"
            default: "Show Album"
            }
            menu.openSystemImage = item.systemImage
        }
        return MusicTileItem(id: item.id, title: item.title, subtitle: item.subtitle, artwork: item.artwork,
                             artworkURL: item.artworkURL, systemImage: item.systemImage, isRound: item.kind == .artist,
                             menu: menu) {
            Task { await media.playRecent(item) }
        }
    }
}
