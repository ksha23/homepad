import Foundation

/// Tiles, shelves and pages for a member's own Apple Music, drawn by the same
/// views as this iPad's. What cannot play here (an upload, a personal
/// station) shows dimmed with the reason in place of its subtitle.
@MainActor
enum MemberMusicTiles {
    /// A tile. Albums, playlists and artists open their page when `opensPage`
    /// (the Library), and play at once otherwise (Listen Now). A song plays
    /// with the songs around it in `list`.
    static func tile(_ item: MemberMusicItem, _ media: AudioMediaService, opensPage: Bool,
                     list: [MemberMusicItem] = [], from playlist: MemberMusicItem? = nil) -> MusicTileItem {
        // A dimmed item says why in place of its subtitle, after the artist when there is one.
        let subtitle = item.unavailableReason.map { reason in [item.subtitle, reason].compactMap { $0 }.joined(separator: " · ") }
        let opens = item.kind == .artist || (opensPage && (item.kind == .album || item.kind == .playlist))
        var tile = MusicTileItem(id: "member:\(item.id)", title: item.title, subtitle: subtitle ?? item.subtitle,
                                 artworkURL: item.artworkURL(), systemImage: symbol(item.kind), isRound: item.kind == .artist) {
            Task {
                if opens {
                    await media.openMember(item)
                } else if item.kind == .song {
                    await media.playMember(songs: list.isEmpty ? [item] : list, startingAt: item, from: playlist)
                } else {
                    await media.playMember(item)
                }
            }
        }
        tile.unavailableReason = item.unavailableReason
        if item.isPlayable { tile.menu = menu(item, media, opensPage: opensPage) }
        return tile
    }

    /// Play or open, and Shuffle, for albums and playlists.
    private static func menu(_ item: MemberMusicItem, _ media: AudioMediaService, opensPage: Bool) -> MusicItemMenu {
        var menu = MusicItemMenu()
        guard item.kind == .album || item.kind == .playlist else { return menu }
        if opensPage {
            menu.play = { Task { await media.playMember(item) } }
        } else {
            menu.open = { Task { await media.openMember(item) } }
            menu.openTitle = item.kind == .playlist ? "Show Playlist" : "Show Album"
            menu.openSystemImage = symbol(item.kind)
        }
        menu.shuffle = { Task { await media.playMember(item, shuffled: true) } }
        return menu
    }

    static func symbol(_ kind: MemberMusicItem.Kind) -> String {
        switch kind {
        case .song: "music.note"
        case .album: "square.stack"
        case .playlist: "music.note.list"
        case .artist: "music.mic"
        case .station: "dot.radiowaves.left.and.right"
        }
    }

    // MARK: Listen Now

    /// Recently Played (what they played on HomePad, then on their own
    /// devices), Apple Music's recommendations for them, their playlists and
    /// what they added lately.
    static func shelves(_ library: MemberMusicLibrary, _ media: AudioMediaService) -> [MusicShelfModel] {
        let snapshot = library.snapshot
        let mine = media.memberRecents.filter { $0.source == .appleMusic || $0.source == .memberLibrary }
        let seen = Set(mine.map { $0.title.lowercased() })
        let history = snapshot.recentlyPlayed.filter { !seen.contains($0.title.lowercased()) }
        var shelves = [MusicShelfModel(title: "Recently Played",
                                       items: mine.map { MusicShelves.recentTile($0, media) } + history.map { tile($0, media, opensPage: false) })]
        shelves += snapshot.recommendations.prefix(4).map { shelf in
            MusicShelfModel(title: shelf.title, items: shelf.items.map { tile($0, media, opensPage: false) })
        }
        shelves.append(MusicShelfModel(title: "Your Playlists",
                                       items: snapshot.playlists.prefix(24).map { tile($0, media, opensPage: false) }))
        shelves.append(MusicShelfModel(title: "Recently Added",
                                       items: snapshot.recentlyAdded.map { tile($0, media, opensPage: false) }))
        return shelves
    }

    // MARK: Library

    static func state(_ kind: LibraryKind, _ library: MemberMusicLibrary, _ media: AudioMediaService) -> LibraryContent.State {
        let snapshot = library.snapshot
        guard snapshot.isLoaded(kind) else {
            if library.loading.contains(kind.rawValue) { return .loading }
            return .empty(library.problem == nil ? "Loading \(library.libraryTitle)." : MemberMusicHeader.problemText(library))
        }
        let items = snapshot.items(kind)
        guard !items.isEmpty else { return .empty("No \(kind.title.lowercased()) in \(library.libraryTitle) yet.") }
        let songs = kind == .songs ? items : []
        return .items(items.map { tile($0, media, opensPage: true, list: songs) })
    }

    // MARK: Their playlist's page

    /// One of the person's own playlists, with its songs. Uploads show dimmed.
    static func playlistDetail(_ playlist: MemberMusicItem, _ media: AudioMediaService) async throws -> MusicDetail {
        guard let library = media.memberMusic.shown else { throw MemberMusicError.unreadable(playlist.title) }
        guard let tracks = await library.tracks(of: playlist) else { throw MemberMusicError.unreadable(playlist.title) }
        let header = MusicTileItem(id: "member:\(playlist.id)", title: playlist.title, subtitle: playlist.subtitle,
                                   artworkURL: playlist.artworkURL(side: 1200), systemImage: "music.note.list") {
            Task { await media.playMember(songs: tracks, startingAt: nil, from: playlist) }
        }
        var actions = MusicItemMenu()
        let playable = tracks.filter(\.isPlayable)
        if !playable.isEmpty {
            actions.play = { Task { await media.playMember(songs: tracks, startingAt: nil, from: playlist) } }
            actions.shuffle = { Task { await media.playMember(songs: tracks, startingAt: nil, from: playlist, shuffled: true) } }
        }
        let total = tracks.compactMap(\.duration).reduce(0, +)
        var detail = MusicDetail(kind: .playlist, title: playlist.title, subtitle: library.libraryTitle,
                                 detail: summary(songs: tracks.count, playable: playable.count, duration: total), header: header)
        detail.tracks = tracks.map { track in
            MusicDetail.Track(item: tile(track, media, opensPage: false, list: tracks, from: playlist), duration: track.duration)
        }
        detail.actions = actions
        return detail
    }

    /// "24 Songs, 1 Hr 30 Min", and how many cannot play here.
    static func summary(songs: Int, playable: Int, duration: TimeInterval) -> String {
        let line = MusicDetail.summary(songCount: songs, duration: duration > 0 ? duration : nil)
        let missing = songs - playable
        guard missing > 0 else { return line }
        return "\(line). \(missing == 1 ? "1 song isn't" : "\(missing) songs aren't") in Apple Music and can't play here."
    }
}
