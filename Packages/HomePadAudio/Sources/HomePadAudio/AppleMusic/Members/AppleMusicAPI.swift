import Foundation
import MusicKit

/// The Apple Music API for one household member: this HomePad's own developer
/// token with that person's Music User Token, sent straight to
/// api.music.apple.com. MusicKit's own requests add the token of the account
/// signed in on this iPad, so they can only ever read the iPad's library.
///
/// The token is a secret. It goes in the `Music-User-Token` header and nowhere
/// else, and nothing here logs a request.
struct AppleMusicAPI: Sendable {
    /// Sends one request. URLSession in the app, recorded answers in tests and the simulator demo.
    typealias Transport = @Sendable (URLRequest) async throws -> (Data, URLResponse)
    /// This HomePad's developer token. `refresh` skips MusicKit's cache.
    typealias DeveloperToken = @Sendable (_ refresh: Bool) async throws -> String

    enum Failure: Error, Equatable {
        /// 401 or 403: the person's token no longer works. It ran out, they
        /// turned off HomePad's access, or their subscription lapsed.
        case tokenRejected(Int)
        /// MusicKit gave this HomePad no developer token (the MusicKit App Service is off).
        case noDeveloperToken
        case http(Int)
        case offline
    }

    let userToken: String
    var transport: Transport = { try await URLSession.shared.data(for: $0) }
    var developerToken: DeveloperToken = { refresh in
        try await DefaultMusicTokenProvider().developerToken(options: refresh ? .ignoreCache : [])
    }

    // MARK: Endpoints

    /// The person's storefront, such as "us".
    func storefront() async throws -> String? {
        try await get("/v1/me/storefront", as: APIPage.self).data.first?.id
    }

    /// One list of the person's library, with each item's catalog match.
    func library(_ kind: LibraryKind, limit: Int) async throws -> [APIResource] {
        try await all("/v1/me/library/\(kind.rawValue)", query: [
            URLQueryItem(name: "include", value: "catalog"), URLQueryItem(name: "limit", value: "100"),
        ], limit: limit)
    }

    /// Albums, playlists and stations the person played lately, on any device.
    func recentlyPlayed(limit: Int = 20) async throws -> [APIResource] {
        try await all("/v1/me/recent/played", query: [
            URLQueryItem(name: "limit", value: "10"),
            URLQueryItem(name: "types", value: "albums,library-albums,playlists,library-playlists,stations"),
        ], limit: limit)
    }

    /// Apple Music's recommendations for the person, each a titled group.
    func recommendations() async throws -> [APIResource] {
        try await get("/v1/me/recommendations", as: APIPage.self).data
    }

    /// The songs of one of the person's own playlists, with each song's catalog match.
    func playlistTracks(_ playlistID: String, limit: Int) async throws -> [APIResource] {
        try await all("/v1/me/library/playlists/\(playlistID)/tracks", query: [
            URLQueryItem(name: "include", value: "catalog"), URLQueryItem(name: "limit", value: "100"),
        ], limit: limit)
    }

    // MARK: Requests

    /// Every page of a list, following `next`, up to `limit` items.
    func all(_ path: String, query: [URLQueryItem], limit: Int) async throws -> [APIResource] {
        var items: [APIResource] = []
        var next: String? = path
        while let current = next, items.count < limit {
            let page = try await get(current, query: query, as: APIPage.self)
            items += page.data
            next = page.data.isEmpty ? nil : page.next
        }
        return Array(items.prefix(limit))
    }

    func get<Body: Decodable>(_ path: String, query: [URLQueryItem] = [], as type: Body.Type) async throws -> Body {
        let data = try await data(path, query: query)
        return try JSONDecoder().decode(Body.self, from: data)
    }

    /// One GET. A 401 is tried once more with a fresh developer token, since a
    /// stale developer token also answers 401. A second 401, or a 403, means
    /// the person's token does not work.
    func data(_ path: String, query: [URLQueryItem]) async throws -> Data {
        guard let url = Self.url(path, query: query) else { throw Failure.http(400) }
        var refresh = false
        while true {
            let developer: String
            do {
                developer = try await developerToken(refresh)
            } catch {
                throw Failure.noDeveloperToken
            }
            var request = URLRequest(url: url)
            request.setValue("Bearer \(developer)", forHTTPHeaderField: "Authorization")
            request.setValue(userToken, forHTTPHeaderField: "Music-User-Token")
            let (data, response): (Data, URLResponse)
            do {
                (data, response) = try await transport(request)
            } catch {
                throw Failure.offline
            }
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            switch status {
            case 200..<300: return data
            case 401 where !refresh: refresh = true
            case 401, 403: throw Failure.tokenRejected(status)
            default: throw Failure.http(status)
            }
        }
    }

    /// The address for a path, which may be a `next` link with its own query.
    /// Parameters the link leaves out (such as `include`) are added again.
    static func url(_ path: String, query: [URLQueryItem]) -> URL? {
        guard var components = URLComponents(string: path) else { return nil }
        components.scheme = "https"
        components.host = "api.music.apple.com"
        var items = components.queryItems ?? []
        for item in query where !items.contains(where: { $0.name == item.name }) { items.append(item) }
        components.queryItems = items.isEmpty ? nil : items
        return components.url
    }
}

// MARK: Responses

/// A page of resources, as every Apple Music API list answers.
struct APIPage: Decodable, Sendable {
    var data: [APIResource]
    var next: String?
}

/// One Apple Music API resource: a song, album, playlist, artist or station,
/// from the catalog or a person's library, or a recommendation. Only the
/// fields HomePad shows are read.
struct APIResource: Decodable, Sendable {
    var id: String
    var type: String
    var attributes: Attributes?
    var relationships: Relationships?

    struct Attributes: Decodable, Sendable {
        var name: String?
        var artistName: String?
        var curatorName: String?
        var artwork: Artwork?
        var durationInMillis: Int?
        var trackNumber: Int?
        var dateAdded: String?
        var playParams: PlayParams?
        /// A recommendation's title.
        var title: Title?
    }

    struct Artwork: Decodable, Sendable {
        /// The address with `{w}` and `{h}` for the size.
        var url: String
    }

    struct PlayParams: Decodable, Sendable {
        var id: String?
        var kind: String?
        var isLibrary: Bool?
        /// A library song's catalog song, when Apple matched it.
        var catalogId: String?
        /// A library playlist's public catalog playlist, when it has one.
        var globalId: String?
    }

    struct Title: Decodable, Sendable {
        var stringForDisplay: String?
    }

    struct Relationships: Decodable, Sendable {
        /// A library item's catalog match. Empty for uploads.
        var catalog: Relationship?
        /// A recommendation's albums, playlists and stations.
        var contents: Relationship?
    }

    struct Relationship: Decodable, Sendable {
        var data: [APIResource]?
    }
}
