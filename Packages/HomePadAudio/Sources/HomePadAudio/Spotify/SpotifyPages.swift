import Foundation
import UIKit

/// Tiles, menus and album, playlist and artist pages for Spotify.
@MainActor
enum SpotifyPages {
    /// A tile. Albums, playlists and artists open their page when `opensPage` is
    /// true, and play otherwise. Tracks play.
    static func tile(_ item: SpotifyItem, _ media: AudioMediaService, opensPage: Bool) -> MusicTileItem {
        let hasPage = [.album, .playlist, .artist].contains(item.kind)
        var menu = MusicItemMenu()
        if hasPage, opensPage {
            menu.play = { Task { await media.playSpotify(item) } }
        } else if hasPage {
            menu.open = { media.pages.push(.spotify(item)) }
            menu.openTitle = "Show \(item.kind == .artist ? "Artist" : item.kind == .album ? "Album" : "Playlist")"
            menu.openSystemImage = item.systemImage
        }
        if item.kind == .track {
            menu.playNext = { Task { await media.addToSpotifyQueue(item) } }
            if let albumID = item.albumID {
                menu.open = { media.pages.push(.spotify(SpotifyItem(kind: .album, id: albumID, name: item.albumName ?? item.name))) }
            }
        }
        return MusicTileItem(id: item.uri, title: item.name, subtitle: item.subtitle, artworkURL: item.imageURL,
                             systemImage: item.systemImage, isRound: item.kind == .artist, menu: menu) {
            if hasPage, opensPage { media.pages.push(.spotify(item)) } else { Task { await media.playSpotify(item) } }
        }
    }

    /// A track in an album or playlist, which plays the rest of it after.
    static func track(_ track: SpotifyItem, in context: SpotifyItem?, _ media: AudioMediaService) -> MusicTileItem {
        var menu = MusicItemMenu()
        menu.playNext = { Task { await media.addToSpotifyQueue(track) } }
        return MusicTileItem(id: track.uri, title: track.name, subtitle: track.subtitle, artworkURL: track.imageURL, menu: menu) {
            Task { await media.playSpotify(track, in: context) }
        }
    }

    static func detail(_ item: SpotifyItem, _ media: AudioMediaService) async throws -> MusicDetail {
        let spotify = media.spotify
        var actions = MusicItemMenu()
        switch item.kind {
        case .album:
            let (album, tracks, json) = try await spotify.album(item.id)
            let context = album ?? item
            actions.play = { Task { await media.playSpotify(context) } }
            let year = json["release_date"]?.stringValue.map { String($0.prefix(4)) }
            let summary = MusicDetail.summary(songCount: tracks.count, duration: tracks.compactMap(\.duration).reduce(0, +))
            return MusicDetail(
                kind: .album, title: context.name, subtitle: context.subtitle,
                detail: [year, summary].compactMap { $0 }.joined(separator: ", "),
                header: tile(context, media, opensPage: false),
                tracks: tracks.enumerated().map { index, track in
                    MusicDetail.Track(item: Self.track(track, in: context, media), number: index + 1, duration: track.duration)
                },
                actions: openInSpotify(context, actions)
            )
        case .playlist:
            let (playlist, tracks, description) = try await spotify.playlist(item.id)
            let context = playlist ?? item
            actions.play = { Task { await media.playSpotify(context) } }
            return MusicDetail(
                kind: .playlist, title: context.name, subtitle: context.subtitle,
                detail: description ?? (tracks.isEmpty
                    ? "Spotify lists the songs of your own playlists only. Play starts this one."
                    : MusicDetail.summary(songCount: tracks.count, duration: tracks.compactMap(\.duration).reduce(0, +))),
                header: tile(context, media, opensPage: false),
                tracks: tracks.map { MusicDetail.Track(item: Self.track($0, in: context, media), duration: $0.duration) },
                actions: openInSpotify(context, actions)
            )
        case .artist:
            let (artist, top, albums) = try await spotify.artist(item.id)
            let context = artist ?? item
            actions.play = { Task { await media.playSpotify(context) } }
            return MusicDetail(
                kind: .artist, title: context.name, subtitle: nil, detail: nil,
                header: tile(context, media, opensPage: false),
                tracksTitle: top.isEmpty ? nil : "Top Songs",
                tracks: top.prefix(10).map { MusicDetail.Track(item: tile($0, media, opensPage: false), duration: $0.duration) },
                shelves: [MusicShelfModel(title: "Albums and Singles", items: albums.map { tile($0, media, opensPage: true) })],
                actions: openInSpotify(context, actions)
            )
        case .track, .episode:
            throw SpotifyError.http(404, "That has no page.")
        }
    }

    /// Spotify asks apps to link back to it.
    private static func openInSpotify(_ item: SpotifyItem, _ menu: MusicItemMenu) -> MusicItemMenu {
        var menu = menu
        if let url = item.webURL ?? URL(string: "https://open.spotify.com/\(item.kind.rawValue)/\(item.id)") {
            menu.open = { SpotifyLinks.open(url) }
            menu.openTitle = "Open Spotify"
            menu.openSystemImage = "arrow.up.forward.app"
        }
        return menu
    }
}

/// Links into the Spotify app, which Spotify asks apps to offer next to its content.
@MainActor
enum SpotifyLinks {
    /// Opens an open.spotify.com link: in the Spotify app when it is installed, on the web otherwise.
    static func open(_ url: URL) {
        UIApplication.shared.open(url)
    }

    /// The Spotify app's own scheme, listed in HomePad's `LSApplicationQueriesSchemes`.
    static let appURL = URL(string: "spotify:")!

    /// True when the Spotify app is on this iPad.
    static var isInstalled: Bool { UIApplication.shared.canOpenURL(appURL) }

    /// Opens the Spotify app, so this iPad shows up as a Spotify Connect device.
    /// Without the app, Spotify's web page opens.
    static func openApp() {
        UIApplication.shared.open(appURL) { opened in
            if !opened { UIApplication.shared.open(URL(string: "https://open.spotify.com")!) }
        }
    }
}
