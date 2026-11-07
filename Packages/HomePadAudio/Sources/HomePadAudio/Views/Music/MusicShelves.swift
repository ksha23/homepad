import Foundation
import HomePadCore
import MusicKit
import SwiftUI

/// Builds the Listen Now shelves for each source as `MusicShelfModel`s, so every
/// source draws with the same views.
@MainActor
enum MusicShelves {
    /// The shelves for the source in use.
    static func current(_ media: AudioMediaService) -> [MusicShelfModel] {
        switch media.musicSource {
        case .musicAssistant: musicAssistant(media)
        case .spotify: spotify(media)
        case .thisIPad: thisIPad(media)
        }
    }

    /// Spotify: the person's own recently played here, then Spotify's, their
    /// playlists, saved albums and followed artists. Spotify content keeps a
    /// screen of its own, as Spotify's design guidelines ask.
    static func spotify(_ media: AudioMediaService) -> [MusicShelfModel] {
        let home = media.spotify.home
        func tiles(_ items: [SpotifyItem]) -> [MusicTileItem] { items.map { SpotifyPages.tile($0, media, opensPage: false) } }
        let mine = media.memberRecents.filter { $0.source == .spotify }
        let seen = Set(mine.map(\.itemID))
        return [
            MusicShelfModel(title: "Recently Played",
                            items: mine.map { recentTile($0, media) } + tiles(home.recentlyPlayed.filter { !seen.contains($0.uri) })),
            MusicShelfModel(title: "Your Playlists", items: tiles(home.playlists)),
            MusicShelfModel(title: "Saved Albums", items: tiles(home.albums)),
            MusicShelfModel(title: "Artists You Follow", items: tiles(home.artists)),
        ]
    }

    /// This iPad: the recognized member's own Apple Music when they linked it,
    /// else Apple Music when the catalog works, else the synced library (the demo in the simulator).
    static func thisIPad(_ media: AudioMediaService) -> [MusicShelfModel] {
        if let library = media.memberMusic.shown { return MemberMusicTiles.shelves(library, media) }
        if media.demo != nil { return demo(media) }
        if media.catalog.status.canBrowseCatalog { return appleMusic(media) }
        return library(media)
    }

    // MARK: Music Assistant

    static func musicAssistant(_ media: AudioMediaService) -> [MusicShelfModel] {
        let home = media.musicAssistant.home
        let playing = media.musicAssistant.activePlayer
        func tiles(_ items: [MAMediaItem]) -> [MusicTileItem] { items.map { tile($0, media, playing: playing) } }
        return [
            MusicShelfModel(title: "Recently Played", items: tiles(home.recentlyPlayed)),
            MusicShelfModel(title: "Your Playlists", items: tiles(home.playlists)),
            MusicShelfModel(title: "Recently Added", items: tiles(home.recentlyAdded)),
            MusicShelfModel(title: "Artists", items: tiles(home.artists)),
            MusicShelfModel(title: "Radio", items: tiles(home.radio)),
        ]
    }

    /// A Music Assistant item that plays on the chosen speaker when tapped.
    static func tile(_ item: MAMediaItem, _ media: AudioMediaService) -> MusicTileItem {
        tile(item, media, playing: media.musicAssistant.activePlayer)
    }

    /// A Music Assistant item, with the active player looked up once by the caller.
    /// Finding it walks every Home Assistant accessory, so a shelf of tiles that
    /// each looked it up walked them once per tile on every redraw.
    static func tile(_ item: MAMediaItem, _ media: AudioMediaService, playing: MusicAssistantPlayer?) -> MusicTileItem {
        let isActive = playing?.isPlaying == true && (playing?.title == item.name || playing?.album == item.name)
        var subtitle = item.subtitle
        if let provider = item.providerName, item.artists.isEmpty || ![.track, .album].contains(item.mediaType) {
            subtitle = "\(item.mediaType.singularTitle) · \(provider)"
        }
        return MusicTileItem(
            id: item.uri, title: item.displayName, subtitle: subtitle, artworkURL: item.imageURL,
            systemImage: item.mediaType.systemImage, isRound: item.mediaType == .artist, isActive: isActive,
            menu: musicAssistantMenu(item, media)
        ) {
            Task { await media.playOnMusicAssistant(item) }
        }
    }

    /// Play Next and Play Later on the chosen speaker. Stations cannot be queued.
    static func musicAssistantMenu(_ item: MAMediaItem, _ media: AudioMediaService) -> MusicItemMenu {
        var menu = MusicItemMenu()
        guard [.track, .album, .playlist, .artist].contains(item.mediaType) else { return menu }
        menu.playNext = { Task { await media.enqueue(item, at: .next) } }
        menu.playLater = { Task { await media.enqueue(item, at: .later) } }
        return menu
    }

    // MARK: Apple Music

    /// Recently Played starts with what the person using HomePad played here,
    /// then the Apple Music account's history, which every person on this iPad shares.
    static func appleMusic(_ media: AudioMediaService) -> [MusicShelfModel] {
        let catalog = media.catalog
        let mine = media.memberRecents.filter { $0.source == .appleMusic }
        let seen = Set(mine.map(\.itemID))
        let history = catalog.recentlyPlayed.filter { !seen.contains($0.id.rawValue) }
        var shelves = [MusicShelfModel(title: "Recently Played",
                                       items: mine.map { recentTile($0, media) } + history.map { tile($0, media) })]
        shelves += catalog.recommendations.prefix(4).map { recommendation in
            MusicShelfModel(title: recommendation.title ?? "Made for You", items: recommendation.items.map { tile($0, media) })
        }
        shelves.append(MusicShelfModel(title: "Your Playlists",
                                       items: catalog.playlists.map { AppleMusicTiles.playlist($0, media, opensPage: false) }))
        shelves.append(MusicShelfModel(title: "Recently Added",
                                       items: catalog.recentlyAdded.map { AppleMusicTiles.album($0, media, opensPage: false) }))
        return shelves
    }

    static func tile(_ item: RecentlyPlayedMusicItem, _ media: AudioMediaService) -> MusicTileItem {
        switch item {
        case .album(let album): AppleMusicTiles.album(album, media, opensPage: false)
        case .playlist(let playlist): AppleMusicTiles.playlist(playlist, media, opensPage: false)
        case .station(let station): AppleMusicTiles.station(station, media)
        @unknown default: MusicTileItem(id: item.id.rawValue, title: item.title, subtitle: item.subtitle, artwork: item.artwork) {}
        }
    }

    static func tile(_ item: MusicPersonalRecommendation.Item, _ media: AudioMediaService) -> MusicTileItem {
        switch item {
        case .album(let album): AppleMusicTiles.album(album, media, opensPage: false)
        case .playlist(let playlist): AppleMusicTiles.playlist(playlist, media, opensPage: false)
        case .station(let station): AppleMusicTiles.station(station, media)
        @unknown default: MusicTileItem(id: item.id.rawValue, title: item.title, subtitle: item.subtitle, artwork: item.artwork) {}
        }
    }

    // MARK: Library

    /// The synced library through MediaPlayer, which works without the MusicKit service.
    static func library(_ media: AudioMediaService) -> [MusicShelfModel] {
        let library = media.mediaLibrary
        func tiles(_ entries: [MediaLibraryBrowser.Entry], symbol: String, round: Bool = false) -> [MusicTileItem] {
            entries.map { entry in
                MusicTileItem(id: "\(entry.id)", title: entry.title, subtitle: entry.subtitle, libraryArtwork: entry.artwork,
                              systemImage: symbol, isRound: round) {
                    Task { await media.perform { try await media.playLibrary(entry) } }
                }
            }
        }
        return [
            MusicShelfModel(title: "Library Playlists", items: tiles(library.playlists, symbol: "music.note.list")),
            MusicShelfModel(title: "Recently Added", items: tiles(library.recentlyAdded, symbol: "square.stack")),
            MusicShelfModel(title: "Artists", items: tiles(library.artists, symbol: "music.mic", round: true)),
        ]
    }

    // MARK: Radio and demo

    static func radioPicks(_ media: AudioMediaService) -> MusicShelfModel {
        MusicShelfModel(title: "Radio Picks", items: media.radioLibrary.curated.map { station in
            MusicTileItem(id: station.id, title: station.name, subtitle: station.subtitle, artworkURL: station.artworkURL,
                          systemImage: "dot.radiowaves.left.and.right",
                          isActive: media.activeKind == .radio && media.radio.station?.id == station.id) {
                Task { await media.perform { try await media.play(station: station) } }
            }
        })
    }

    /// Simulator stand-ins for Apple Music on the iPad, led by the person's own Recently Played.
    static func demo(_ media: AudioMediaService) -> [MusicShelfModel] {
        func demoTiles(_ items: [MAMediaItem]) -> [MusicTileItem] { items.map { DemoMusicPages.tile($0, media, opensPage: false) } }
        let mine = media.memberRecents.filter { $0.source == .demo }.map { recentTile($0, media) }
        let seen = Set(mine.map(\.title))
        return [
            MusicShelfModel(title: "Recently Played",
                            items: mine + demoTiles(DemoMusicCatalog.albums.prefix(8).filter { !seen.contains($0.name) })),
            MusicShelfModel(title: "Made for You", items: demoTiles(DemoMusicCatalog.playlists)),
            MusicShelfModel(title: "Recently Added", items: demoTiles(DemoMusicCatalog.albums.reversed())),
            MusicShelfModel(title: "Artists", items: demoTiles(DemoMusicCatalog.artists)),
        ]
    }
}
