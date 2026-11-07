import Foundation
import HomePadCore

/// What Listen Now shows for Spotify.
struct SpotifyHome: Equatable {
    var recentlyPlayed: [SpotifyItem] = []
    var playlists: [SpotifyItem] = []
    var albums: [SpotifyItem] = []
    var artists: [SpotifyItem] = []
    var likedSongs: [SpotifyItem] = []

    var isEmpty: Bool {
        recentlyPlayed.isEmpty && playlists.isEmpty && albums.isEmpty && artists.isEmpty && likedSongs.isEmpty
    }
}

/// The answer of `GET /search`, at most 10 of each kind (Spotify's limit for
/// development apps since February 2026).
struct SpotifySearchResults: Equatable {
    var tracks: [SpotifyItem] = []
    var artists: [SpotifyItem] = []
    var albums: [SpotifyItem] = []
    var playlists: [SpotifyItem] = []

    init(json: JSONValue) {
        tracks = SpotifyItem.list(json["tracks"]?["items"])
        artists = SpotifyItem.list(json["artists"]?["items"])
        albums = SpotifyItem.list(json["albums"]?["items"])
        playlists = SpotifyItem.list(json["playlists"]?["items"])
    }

    var isEmpty: Bool { tracks.isEmpty && artists.isEmpty && albums.isEmpty && playlists.isEmpty }
}

/// Listen Now, the Library section, search and pages, from the Web API's
/// library and catalog endpoints. Each request fails on its own, so one
/// missing permission never blanks a screen.
extension SpotifyService {
    func loadHome() async {
        guard hasSignIn else { return }
        let epoch = accountEpoch
        isLoadingHome = true
        defer { if isCurrent(epoch) { isLoadingHome = false } }
        let client = client
        async let recent = try? client.get("me/player/recently-played", query: ["limit": "20"])
        async let playlists = try? client.get("me/playlists", query: ["limit": "30"])
        async let albums = try? client.get("me/albums", query: ["limit": "30"])
        async let artists = try? client.get("me/following", query: ["type": "artist", "limit": "30"])
        async let liked = try? client.get("me/tracks", query: ["limit": "20"])
        var loaded = SpotifyHome()
        loaded.recentlyPlayed = Self.unique(SpotifyItem.list(await recent?["items"], unwrapping: ["track"]))
        loaded.playlists = SpotifyItem.list(await playlists?["items"])
        loaded.albums = SpotifyItem.list(await albums?["items"], unwrapping: ["album"])
        loaded.artists = SpotifyItem.list(await artists?["artists"]?["items"])
        loaded.likedSongs = SpotifyItem.list(await liked?["items"], unwrapping: ["track"])
        // Someone else's account took over while these loaded.
        guard isCurrent(epoch) else { return }
        home = loaded
        hasLoadedHome = true
    }

    /// One Library list, the first time it is shown.
    func loadLibrary(_ kind: LibraryKind, force: Bool = false) async {
        guard hasSignIn, force || library[kind] == nil else { return }
        let epoch = accountEpoch
        let items: [SpotifyItem]
        do {
            switch kind {
            case .playlists: items = SpotifyItem.list(try await client.get("me/playlists", query: ["limit": "50"])["items"])
            case .albums: items = SpotifyItem.list(try await client.get("me/albums", query: ["limit": "50"])["items"], unwrapping: ["album"])
            case .artists:
                items = SpotifyItem.list(try await client.get("me/following", query: ["type": "artist", "limit": "50"])["artists"]?["items"])
            case .songs: items = SpotifyItem.list(try await client.get("me/tracks", query: ["limit": "50"])["items"], unwrapping: ["track"])
            }
        } catch {
            if isCurrent(epoch) { note(error) }
            items = []
        }
        guard isCurrent(epoch) else { return }
        library[kind] = items
    }

    func search(_ query: String) async {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard hasSignIn, !trimmed.isEmpty else {
            searchResults = nil
            return
        }
        let epoch = accountEpoch
        isSearching = true
        defer { if isCurrent(epoch) { isSearching = false } }
        do {
            let json = try await client.get("search", query: ["q": trimmed, "type": "track,artist,album,playlist", "limit": "10"])
            guard isCurrent(epoch) else { return }
            searchResults = SpotifySearchResults(json: json)
        } catch {
            guard isCurrent(epoch) else { return }
            note(error)
            searchResults = SpotifySearchResults(json: .null)
        }
    }

    // MARK: Pages

    /// An album with its tracks. Simplified tracks carry no artwork, so they take the album's.
    func album(_ id: String) async throws -> (album: SpotifyItem?, tracks: [SpotifyItem], json: JSONValue) {
        let json = try await client.get("albums/\(id)")
        let album = SpotifyItem(json: json, kind: .album)
        let tracks = SpotifyItem.list(json["tracks"]?["items"], kind: .track).map { track in
            var track = track
            track.imageURL = track.imageURL ?? album?.imageURL
            track.albumName = album?.name
            return track
        }
        return (album, tracks, json)
    }

    /// A playlist and its songs. Since February 2026 Spotify lists the songs of
    /// playlists the person owns or collaborates on only, and renamed `/tracks` to `/items`.
    func playlist(_ id: String) async throws -> (playlist: SpotifyItem?, tracks: [SpotifyItem], description: String?) {
        let json = try await client.get("playlists/\(id)")
        let playlist = SpotifyItem(json: json, kind: .playlist)
        var tracks: [SpotifyItem] = []
        if let page = try? await client.get("playlists/\(id)/items", query: ["limit": "100"]) {
            tracks = SpotifyItem.list(page["items"], unwrapping: ["item", "track"])
        } else if let page = try? await client.get("playlists/\(id)/tracks", query: ["limit": "100"]) {
            tracks = SpotifyItem.list(page["items"], unwrapping: ["track", "item"])
        }
        let description = json["description"]?.stringValue.flatMap { $0.isEmpty ? nil : Self.plainText($0) }
        return (playlist, tracks, description)
    }

    /// An artist's albums and singles, and top tracks where Spotify still offers them
    /// (removed for development apps made since February 2026).
    func artist(_ id: String) async throws -> (artist: SpotifyItem?, topTracks: [SpotifyItem], albums: [SpotifyItem]) {
        let json = try await client.get("artists/\(id)")
        async let albums = try? client.get("artists/\(id)/albums", query: ["include_groups": "album,single", "limit": "20"])
        async let top = try? client.get("artists/\(id)/top-tracks", query: ["market": "from_token"])
        return (SpotifyItem(json: json, kind: .artist), SpotifyItem.list(await top?["tracks"]), SpotifyItem.list(await albums?["items"]))
    }

    /// The same track played twice in a row shows once.
    private static func unique(_ items: [SpotifyItem]) -> [SpotifyItem] {
        var seen = Set<String>()
        return items.filter { seen.insert($0.uri).inserted }
    }

    /// Spotify playlist descriptions may hold simple HTML.
    static func plainText(_ html: String) -> String {
        html.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&#x27;", with: "'")
            .replacingOccurrences(of: "&quot;", with: "\"")
    }
}
