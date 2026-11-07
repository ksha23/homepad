import Foundation

/// `-HomePadMemberMusicDemo YES`: in the simulator, the member recognized here
/// (`-HomePadDemoContent YES -HomePadMember Alex -HomePadRecognized YES`) has a
/// made-up Apple Music. It answers in the Apple Music API's own JSON shapes,
/// so the decoding and the playable rule run as on a device. Nothing goes to
/// Apple. The catalog IDs are made up, so playing them fails in the simulator.
enum MemberMusicDemo {
    static var isEnabled: Bool { UserDefaults.standard.bool(forKey: "HomePadMemberMusicDemo") }

    static func api(userToken: String) -> AppleMusicAPI {
        var api = AppleMusicAPI(userToken: userToken)
        api.developerToken = { _ in "demo-developer-token" }
        api.transport = { request in
            let url = request.url ?? URL(string: "https://api.music.apple.com")!
            let body = (try? JSONSerialization.data(withJSONObject: ["data": resources(for: url.path)])) ?? Data()
            let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil) ?? URLResponse()
            return (body, response)
        }
        return api
    }

    /// The resources each endpoint answers with.
    private static func resources(for path: String) -> [[String: Any]] {
        switch path {
        case "/v1/me/storefront":
            return [["id": "us", "type": "storefronts", "attributes": ["name": "United States"]]]
        case "/v1/me/recent/played":
            return [album("1001", "Night Signals", "The Lanterns"), station("ra.1002", "Indie Chill Station"),
                    album("1003", "Golden Hours", "Mara Vale"), station("ra.u-demo", "Alex's Station"),
                    album("1004", "Paper Planes", "Northbound")]
        case "/v1/me/recommendations":
            return [
                recommendation("Made for You", [playlist("pl.2001", "Favorites Mix"), playlist("pl.2002", "Chill Mix"),
                                                playlist("pl.2003", "New Music Mix")]),
                recommendation("New Releases for You", [album("2101", "Static Bloom", "Cassette Kids"),
                                                        album("2102", "Low Tide", "Harbor Lights"), album("2103", "Overpass", "Neon Avenue")]),
            ]
        case "/v1/me/library/playlists":
            return [libraryPlaylist("p.road", "Road Trip"), libraryPlaylist("p.run", "Morning Run"),
                    libraryPlaylist("p.dinner", "Dinner Party"), libraryPlaylist("p.focus", "Deep Focus"),
                    libraryPlaylist("p.chill", "Chill Mix", catalog: "pl.2002")]
        case "/v1/me/library/albums":
            return [libraryAlbum("l.a1", "Night Signals", "The Lanterns", catalog: "1001", added: "2026-10-30"),
                    libraryAlbum("l.a2", "Golden Hours", "Mara Vale", catalog: "1003", added: "2026-10-21"),
                    libraryAlbum("l.a3", "Garage Demos", "Alex", catalog: nil, added: "2026-10-18"),
                    libraryAlbum("l.a4", "Paper Planes", "Northbound", catalog: "1004", added: "2026-09-02"),
                    libraryAlbum("l.a5", "Static Bloom", "Cassette Kids", catalog: "2101", added: "2026-08-14"),
                    libraryAlbum("l.a6", "Harbor Nights", "Harbor Lights", catalog: "1006", added: "2026-07-01")]
        case "/v1/me/library/artists":
            return [libraryArtist("r.1", "Cassette Kids", catalog: "3001"), libraryArtist("r.2", "Harbor Lights", catalog: "3002"),
                    libraryArtist("r.3", "Mara Vale", catalog: "3003"), libraryArtist("r.4", "The Lanterns", catalog: "3004")]
        case "/v1/me/library/songs":
            return songs
        default:
            if path.hasPrefix("/v1/me/library/playlists/") { return songs }
            return []
        }
    }

    private static let songs: [[String: Any]] = [
        librarySong("i.1", "Afterglow", "The Lanterns", catalog: "4001"),
        librarySong("i.2", "Coastline", "Harbor Lights", catalog: "4002"),
        librarySong("i.3", "Basement Take 3", "Alex", catalog: nil),
        librarySong("i.4", "Golden Hours", "Mara Vale", catalog: "4004"),
        librarySong("i.5", "Paper Planes", "Northbound", catalog: "4005"),
        librarySong("i.6", "Voice Memo Jam", "Alex", catalog: nil),
        librarySong("i.7", "Static Bloom", "Cassette Kids", catalog: "4007"),
    ]

    // MARK: Resources in the API's shapes

    private static func artwork(_ name: String) -> [String: Any]? {
        AudioDemo.artworkURL(for: name).map { ["url": $0.absoluteString] }
    }

    private static func attributes(_ name: String, _ extra: [String: Any?] = [:]) -> [String: Any] {
        var attributes: [String: Any] = ["name": name]
        if let art = artwork(name) { attributes["artwork"] = art }
        for (key, value) in extra { if let value { attributes[key] = value } }
        return attributes
    }

    private static func catalog(_ id: String?, type: String) -> [String: Any] {
        ["catalog": ["data": id.map { [["id": $0, "type": type]] } ?? []]]
    }

    private static func album(_ id: String, _ name: String, _ artist: String) -> [String: Any] {
        ["id": id, "type": "albums", "attributes": attributes(name, ["artistName": artist])]
    }

    private static func playlist(_ id: String, _ name: String) -> [String: Any] {
        ["id": id, "type": "playlists", "attributes": attributes(name, ["curatorName": "Apple Music"])]
    }

    private static func station(_ id: String, _ name: String) -> [String: Any] {
        ["id": id, "type": "stations", "attributes": attributes(name)]
    }

    private static func recommendation(_ title: String, _ contents: [[String: Any]]) -> [String: Any] {
        ["id": "rec.\(title)", "type": "personal-recommendation",
         "attributes": ["title": ["stringForDisplay": title], "kind": "music-recommendations"],
         "relationships": ["contents": ["data": contents]]]
    }

    private static func libraryPlaylist(_ id: String, _ name: String, catalog id2: String? = nil) -> [String: Any] {
        ["id": id, "type": "library-playlists",
         "attributes": attributes(name, ["playParams": ["id": id, "kind": "playlist", "isLibrary": true]]),
         "relationships": catalog(id2, type: "playlists")]
    }

    private static func libraryAlbum(_ id: String, _ name: String, _ artist: String, catalog id2: String?, added: String) -> [String: Any] {
        ["id": id, "type": "library-albums",
         "attributes": attributes(name, ["artistName": artist, "dateAdded": added,
                                         "playParams": ["id": id, "kind": "album", "isLibrary": true]]),
         "relationships": catalog(id2, type: "albums")]
    }

    private static func libraryArtist(_ id: String, _ name: String, catalog id2: String) -> [String: Any] {
        ["id": id, "type": "library-artists", "attributes": ["name": name], "relationships": catalog(id2, type: "artists")]
    }

    private static func librarySong(_ id: String, _ name: String, _ artist: String, catalog id2: String?) -> [String: Any] {
        var playParams: [String: Any] = ["id": id, "kind": "song", "isLibrary": true]
        if let id2 { playParams["catalogId"] = id2 }
        return ["id": id, "type": "library-songs",
                "attributes": attributes(name, ["artistName": artist, "albumName": name, "durationInMillis": 214_000,
                                                "playParams": playParams]),
                "relationships": catalog(id2, type: "songs")]
    }
}
