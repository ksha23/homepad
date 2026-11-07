import Foundation

/// Album, playlist and artist pages and tiles for the simulator demo, built
/// like Apple Music's so the screens can be checked without MusicKit.
@MainActor
enum DemoMusicPages {
    static func detail(_ item: MAMediaItem, _ media: AudioMediaService) -> MusicDetail {
        let tracks = DemoMusicCatalog.queue(for: item)
        let kind: MusicDetail.Kind = switch item.mediaType {
        case .artist: .artist
        case .playlist: .playlist
        default: .album
        }
        let rows = tracks.enumerated().map { index, track in
            MusicDetail.Track(
                item: MusicTileItem(id: "\(item.uri)#\(index)", title: track.title,
                                    subtitle: kind == .album ? nil : track.artist,
                                    artworkURL: AudioDemo.artworkURL(for: track.album), action: {
                                        media.playDemo(tracks, startingAt: index, origin: item.name)
                                    }).with(trackMenu(track, media)),
                number: kind == .album ? index + 1 : nil, duration: track.duration
            )
        }
        var actions = MusicItemMenu()
        actions.play = { media.playDemo(tracks, origin: item.name) }
        actions.shuffle = { media.playDemo(tracks, origin: item.name, shuffled: true) }
        actions.playNext = { media.enqueueDemo(matching: item.name, at: .next) }
        actions.playLater = { media.enqueueDemo(matching: item.name, at: .later) }
        if kind == .album, let artist = tracks.first?.artist {
            actions.open = { media.pages.push(.demo(artistItem(artist))) }
            actions.openTitle = "Show Artist"
            actions.openSystemImage = "music.mic"
        }
        let albums = kind == .artist ? DemoMusicCatalog.albums.filter { $0.artists.contains(item.name) } : []
        return MusicDetail(
            kind: kind, title: item.name, subtitle: kind == .album ? tracks.first?.artist : (kind == .playlist ? "HomePad" : nil),
            detail: kind == .artist ? nil : MusicDetail.summary(songCount: tracks.count, duration: tracks.map(\.duration).reduce(0, +)),
            header: MusicTileItem(id: item.uri, title: item.name, subtitle: nil,
                                  artworkURL: kind == .album ? AudioDemo.artworkURL(for: item.name) : nil,
                                  systemImage: item.mediaType.systemImage, isRound: kind == .artist) {
                media.playDemo(tracks, origin: item.name)
            },
            tracksTitle: kind == .artist ? "Top Songs" : nil, tracks: rows,
            shelves: [MusicShelfModel(title: "Albums", items: albums.map { tile($0, media, opensPage: true) })],
            actions: actions
        )
    }

    /// A demo tile. Albums, playlists and artists open their page when `opensPage` is true.
    static func tile(_ item: MAMediaItem, _ media: AudioMediaService, opensPage: Bool) -> MusicTileItem {
        let hasPage = [.album, .playlist, .artist].contains(item.mediaType)
        var menu = MusicItemMenu()
        if hasPage, opensPage {
            menu.play = { media.playDemo(matching: item.name) }
        } else if hasPage {
            menu.open = { media.pages.push(.demo(item)) }
            menu.openTitle = item.mediaType == .artist ? "Show Artist" : "Show \(item.mediaType.singularTitle)"
            menu.openSystemImage = item.mediaType.systemImage
        }
        if item.mediaType != .radio {
            menu.playNext = { media.enqueueDemo(matching: item.name, at: .next) }
            menu.playLater = { media.enqueueDemo(matching: item.name, at: .later) }
        }
        let artwork = item.mediaType == .album ? AudioDemo.artworkURL(for: item.name) : nil
        return MusicTileItem(id: item.uri, title: item.name, subtitle: item.subtitle, artworkURL: artwork,
                             systemImage: item.mediaType.systemImage, isRound: item.mediaType == .artist, menu: menu) {
            if hasPage, opensPage { media.pages.push(.demo(item)) } else { media.playDemo(matching: item.name) }
        }
    }

    private static func trackMenu(_ track: DemoMusicCatalog.Track, _ media: AudioMediaService) -> MusicItemMenu {
        var menu = MusicItemMenu()
        menu.playNext = { media.enqueueDemo(matching: track.title, at: .next) }
        menu.playLater = { media.enqueueDemo(matching: track.title, at: .later) }
        if let album = DemoMusicCatalog.albums.first(where: { $0.name == track.album }) {
            menu.open = { media.pages.push(.demo(album)) }
        }
        return menu
    }

    static func artistItem(_ name: String) -> MAMediaItem {
        DemoMusicCatalog.artists.first { $0.name == name } ?? MAMediaItem(mediaType: .artist, uri: "demo://artist/\(name)", name: name)
    }
}

extension AudioMediaService {
    /// Plays a demo song on the iPad, for simulator screenshots.
    func playDemo(matching text: String, shuffled: Bool = false) {
        guard let demo else { return }
        activate(.demo)
        demo.play(matching: text, shuffled: shuffled)
    }

    /// Plays demo songs from a page, starting at one of them.
    func playDemo(_ tracks: [DemoMusicCatalog.Track], startingAt start: Int = 0, origin: String?, shuffled: Bool = false) {
        guard let demo else { return }
        activate(.demo)
        demo.play(tracks, startingAt: start, origin: origin, shuffled: shuffled)
    }
}
