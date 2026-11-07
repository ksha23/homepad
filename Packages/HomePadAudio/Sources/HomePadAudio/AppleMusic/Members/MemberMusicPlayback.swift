import Foundation
import HomePadCore
import MusicKit

/// Playing a member's own Apple Music on this iPad.
///
/// The iPad's player plays only through the iPad's own account, so each item
/// is looked up again in the catalog, here, by its catalog ID, and played from
/// there. What plays counts toward the iPad's account. A song the person
/// uploaded has no catalog ID and cannot play. Queues, places and Recently
/// Played stay per person as for anything else (`+Members`), since what
/// plays is catalog music the iPad can find again.
extension AudioMediaService {
    /// Plays an item from the shown member's Apple Music. A song plays with
    /// the songs around it in `list`, and `playlist` is where the list came from.
    func playMember(_ item: MemberMusicItem, in list: [MemberMusicItem] = [], from playlist: MemberMusicItem? = nil,
                    shuffled: Bool = false) async {
        await performMember { try await startMember(item, in: list, from: playlist, shuffled: shuffled) }
    }

    /// Plays a list of their songs, such as a playlist's, from `start` on.
    func playMember(songs list: [MemberMusicItem], startingAt start: MemberMusicItem?, from playlist: MemberMusicItem?,
                    shuffled: Bool = false) async {
        await performMember { try await startMemberSongs(list, startingAt: start, from: playlist, shuffled: shuffled) }
    }

    /// Opens an item's page: the catalog album or artist it matches, a
    /// catalog playlist, or their own playlist with its songs.
    func openMember(_ item: MemberMusicItem) async {
        await performMember {
            switch item.kind {
            case .album:
                pages.push(.appleMusicAlbum(try await MemberCatalog.album(item)))
            case .artist:
                pages.push(.appleMusicArtist(try await MemberCatalog.artist(item)))
            case .playlist:
                if !item.isLibrary || item.catalogID?.hasPrefix("pl.") == true,
                   let playlist = try? await MemberCatalog.playlist(item) {
                    pages.push(.appleMusicPlaylist(playlist))
                } else {
                    pages.push(.memberPlaylist(item))
                }
            case .song, .station:
                try await startMember(item, in: [], from: nil, shuffled: false)
            }
        }
    }

    // MARK: Starting

    func startMember(_ item: MemberMusicItem, in list: [MemberMusicItem], from playlist: MemberMusicItem?,
                     shuffled: Bool) async throws {
        if let reason = item.unavailableReason { throw MemberMusicError.cannotPlay(item.title, reason) }
        _ = await appleMusic.requestAuthorization()
        switch item.kind {
        case .song:
            try await startMemberSongs(list.isEmpty ? [item] : list, startingAt: item, from: playlist, shuffled: shuffled)
        case .album:
            let album = try await MemberCatalog.album(item)
            try await startAppleMusic(recent: .appleMusic(album)) { try await appleMusic.play(album, shuffled: shuffled) }
        case .station:
            let station = try await MemberCatalog.station(item)
            try await startAppleMusic(recent: .appleMusic(station)) { try await appleMusic.play(station) }
        case .artist:
            let artist = try await MemberCatalog.artist(item)
            let songs = try await AppleMusicPages.topSongs(of: artist)
            guard let first = songs.first else { throw MemberMusicError.notInThisCatalog(item.title) }
            try await startAppleMusic(recent: .appleMusic(artist)) {
                try await appleMusic.play(songs, startingAt: shuffled ? nil : first, shuffled: shuffled)
            }
        case .playlist:
            try await startMemberPlaylist(item, shuffled: shuffled)
        }
    }

    /// A catalog playlist plays as itself. The person's own playlist plays as
    /// the catalog songs in it, in its order, and shows as "Playing from" its name.
    func startMemberPlaylist(_ item: MemberMusicItem, shuffled: Bool) async throws {
        if item.catalogID?.hasPrefix("pl.") == true, let playlist = try? await MemberCatalog.playlist(item) {
            try await startAppleMusic(recent: .appleMusic(playlist)) { try await appleMusic.play(playlist, shuffled: shuffled) }
            return
        }
        guard let library = memberMusic.shown, let tracks = await library.tracks(of: item) else {
            throw MemberMusicError.unreadable(item.title)
        }
        try await startMemberSongs(tracks, startingAt: nil, from: item, shuffled: shuffled)
    }

    func startMemberSongs(_ list: [MemberMusicItem], startingAt start: MemberMusicItem?, from playlist: MemberMusicItem?,
                          shuffled: Bool) async throws {
        let ids = list.filter(\.isPlayable).compactMap(\.catalogID)
        guard !ids.isEmpty else { throw MemberMusicError.cannotPlay(playlist?.title ?? start?.title ?? "That", "Not in Apple Music") }
        let songs = try await MemberCatalog.songs(ids)
        guard !songs.isEmpty else { throw MemberMusicError.notInThisCatalog(playlist?.title ?? start?.title ?? "That") }
        let first = start.flatMap { start in songs.first { $0.id.rawValue == start.catalogID } }
        let recent = playlist.map(RecentMusicItem.memberPlaylist) ?? (first ?? songs.first).flatMap { RecentMusicItem.appleMusic($0) }
        try await startAppleMusic(recent: recent) {
            try await appleMusic.play(songs, startingAt: shuffled ? nil : first, shuffled: shuffled)
        }
        if let playlist { appleMusic.originTitle = playlist.title }
    }

    // MARK: The assistant

    /// "Play my playlist Road Trip": the recognized member's own playlist,
    /// when they linked their Apple Music and the request is about their own
    /// music. Nil when it is not, so the catalog search runs as before.
    func playFromMemberLibrary(_ query: String) async throws -> String? {
        guard musicSource == .thisIPad, let library = memberMusic.shown, MemberLibraryMatch.asksForOwnLibrary(query) else { return nil }
        guard let playlist = MemberLibraryMatch.playlist(for: query, in: await library.allPlaylists()) else { return nil }
        _ = await appleMusic.requestAuthorization()
        try await startMemberPlaylist(playlist, shuffled: false)
        memberMusic.notice = nil
        return "the playlist \(playlist.title) from \(library.libraryTitle)"
    }

    // MARK: Recently Played

    /// Plays a Recently Played entry of the member's own playlist again, while they are recognized.
    func playMemberRecent(_ recent: RecentMusicItem) async {
        guard let library = memberMusic.shown else {
            lastError = "That playlist plays while HomePad recognizes the person it belongs to."
            return
        }
        let item = library.snapshot.playlists.first { $0.id == recent.itemID } ?? MemberMusicItem(recent)
        await playMember(item)
    }

    /// Opens a Recently Played entry of the member's own playlist, while they are recognized.
    func openMemberRecent(_ recent: RecentMusicItem) {
        guard let library = memberMusic.shown else { return }
        pages.push(.memberPlaylist(library.snapshot.playlists.first { $0.id == recent.itemID } ?? MemberMusicItem(recent)))
    }

    private func performMember(_ action: () async throws -> Void) async {
        do {
            try await action()
            memberMusic.notice = nil
            lastError = nil
        } catch {
            memberMusic.notice = error.localizedDescription
            lastError = error.localizedDescription
        }
    }
}

/// Catalog lookups on this iPad, in the iPad account's country, for items
/// from a member's own Apple Music.
@MainActor
enum MemberCatalog {
    static func album(_ item: MemberMusicItem) async throws -> Album {
        guard let id = item.catalogID,
              let found = try await MusicCatalogResourceRequest<Album>(matching: \.id, equalTo: MusicItemID(id)).response().items.first
        else { throw MemberMusicError.notInThisCatalog(item.title) }
        return found
    }

    static func playlist(_ item: MemberMusicItem) async throws -> Playlist {
        guard let id = item.catalogID,
              let found = try await MusicCatalogResourceRequest<Playlist>(matching: \.id, equalTo: MusicItemID(id)).response().items.first
        else { throw MemberMusicError.notInThisCatalog(item.title) }
        return found
    }

    static func station(_ item: MemberMusicItem) async throws -> Station {
        guard let id = item.catalogID,
              let found = try await MusicCatalogResourceRequest<Station>(matching: \.id, equalTo: MusicItemID(id)).response().items.first
        else { throw MemberMusicError.notInThisCatalog(item.title) }
        return found
    }

    static func artist(_ item: MemberMusicItem) async throws -> Artist {
        guard let id = item.catalogID,
              let found = try await MusicCatalogResourceRequest<Artist>(matching: \.id, equalTo: MusicItemID(id)).response().items.first
        else { throw MemberMusicError.notInThisCatalog(item.title) }
        return found
    }

    /// Catalog songs by ID, in the order asked, a hundred at a time. Songs
    /// this iPad's country does not have are left out.
    static func songs(_ ids: [String]) async throws -> [Song] {
        var found: [MusicItemID: Song] = [:]
        for start in stride(from: 0, to: ids.count, by: 100) {
            let chunk = ids[start..<min(start + 100, ids.count)].map { MusicItemID($0) }
            let request = MusicCatalogResourceRequest<Song>(matching: \.id, memberOf: chunk)
            for song in try await request.response().items { found[song.id] = song }
        }
        return ids.compactMap { found[MusicItemID($0)] }
    }
}

/// Why one of a member's items did not play here.
enum MemberMusicError: LocalizedError, Equatable {
    case cannotPlay(String, String)
    case notInThisCatalog(String)
    case unreadable(String)

    var errorDescription: String? {
        switch self {
        case .cannotPlay(let title, let reason): "\(title) can't play on this iPad: \(reason.lowercased())."
        case .notInThisCatalog(let title): "\(title) isn't available to the Apple Music account on this iPad."
        case .unreadable(let title): "HomePad couldn't read the songs in \(title) right now."
        }
    }
}

extension RecentMusicItem {
    /// A Recently Played entry for a member's own playlist, which only their token can read.
    static func memberPlaylist(_ item: MemberMusicItem) -> RecentMusicItem {
        RecentMusicItem(source: .memberLibrary, kind: .playlist, itemID: item.id, title: item.title,
                        subtitle: item.subtitle, artworkURL: item.artworkURL())
    }
}

extension MemberMusicItem {
    /// A playlist from its Recently Played entry, for when the library has not listed it yet.
    init(_ recent: RecentMusicItem) {
        self.init(id: recent.itemID, kind: .playlist, title: recent.title, subtitle: recent.subtitle,
                  artworkTemplate: recent.artworkURL?.absoluteString, catalogID: nil, isLibrary: true)
    }
}

/// Finds the playlist a spoken request names in a member's own playlists.
enum MemberLibraryMatch {
    /// Words that say how to play, not what. Taken out of both the request and the names.
    private static let filler: Set<String> = ["play", "my", "playlist", "the", "called", "named", "please", "from", "library", "shuffle"]

    /// True when a request is about the person's own music, as "play my
    /// Road Trip" or "the playlist Road Trip" are, and "play Road Trip" is not.
    static func asksForOwnLibrary(_ query: String) -> Bool {
        let words = words(in: query)
        return words.contains("my") || words.contains("playlist")
    }

    /// The best match: the same name, then a name that starts with the
    /// request, then one that contains it. Nil when nothing comes close.
    static func playlist(for query: String, in playlists: [MemberMusicItem]) -> MemberMusicItem? {
        let wanted = normalize(query)
        guard !wanted.isEmpty else { return nil }
        let named = playlists.filter { $0.kind == .playlist }.map { ($0, normalize($0.title)) }.filter { !$0.1.isEmpty }
        return named.first { $0.1 == wanted }?.0
            ?? named.first { $0.1.hasPrefix(wanted + " ") }?.0
            ?? named.first { $0.1.contains(wanted) }?.0
    }

    /// Lowercased words without accents or filler, joined by single spaces.
    static func normalize(_ text: String) -> String {
        words(in: text).filter { !filler.contains($0) }.joined(separator: " ")
    }

    private static func words(in text: String) -> [String] {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
    }
}
