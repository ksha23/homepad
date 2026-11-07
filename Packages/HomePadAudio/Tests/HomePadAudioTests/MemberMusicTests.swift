import Foundation
import HomePadCore
import Testing
@testable import HomePadAudio

/// Answers Apple Music API requests from the fixtures, and notes what was asked.
final class RecordedAppleMusic: @unchecked Sendable {
    private let lock = NSLock()
    private var asked: [URLRequest] = []
    /// The status for each developer token, 200 when not listed.
    var statusByDeveloperToken: [String: Int] = [:]
    var status = 200

    var requests: [URLRequest] { lock.withLock { asked } }

    func api(userToken: String = "member-token", developerTokens: [String] = ["dev-token"]) -> AppleMusicAPI {
        var api = AppleMusicAPI(userToken: userToken)
        let tokens = developerTokens
        api.developerToken = { refresh in refresh ? tokens.last! : tokens.first! }
        api.transport = { [self] request in try self.answer(request) }
        return api
    }

    private func answer(_ request: URLRequest) throws -> (Data, URLResponse) {
        lock.withLock { asked.append(request) }
        guard let url = request.url else { throw URLError(.badURL) }
        let developer = request.value(forHTTPHeaderField: "Authorization")?.replacingOccurrences(of: "Bearer ", with: "") ?? ""
        let code = statusByDeveloperToken[developer] ?? status
        let response = HTTPURLResponse(url: url, statusCode: code, httpVersion: nil, headerFields: nil)!
        guard code == 200 else { return (Data(#"{"errors":[{"status":"\#(code)"}]}"#.utf8), response) }
        let offset = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "offset" }?.value
        let name = switch (url.path, offset) {
        case ("/v1/me/library/songs", nil): "applemusic_library_songs_page1"
        case ("/v1/me/library/songs", _): "applemusic_library_songs_page2"
        case ("/v1/me/library/playlists", _): "applemusic_library_playlists"
        case ("/v1/me/library/albums", _): "applemusic_library_albums"
        case ("/v1/me/recent/played", _): "applemusic_recent_played"
        case ("/v1/me/recommendations", _): "applemusic_recommendations"
        default: ""
        }
        guard !name.isEmpty, let file = Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures") else {
            return (Data(#"{"data":[]}"#.utf8), response)
        }
        return (try Data(contentsOf: file), response)
    }
}

@Suite("A member's own Apple Music")
struct MemberMusicTests {
    // MARK: Decoding

    @Test("Library songs decode across pages, with both tokens on every request")
    func decodesLibrarySongsAcrossPages() async throws {
        let recorded = RecordedAppleMusic()
        let items = MemberMusicItem.list(try await recorded.api().library(.songs, limit: 300))

        #expect(items.map(\.title) == ["Blue in Green", "Basement Take 3", "Get Lucky"])
        #expect(items.map(\.catalogID) == ["268443097", nil, "617154366"])
        let allLibrarySongs = items.allSatisfy { $0.isLibrary && $0.kind == .song }
        #expect(allLibrarySongs)
        #expect(items[0].duration == 337.56)
        #expect(items[0].artworkURL(side: 300)?.absoluteString == "https://is1-ssl.mzstatic.com/image/thumb/Music/v4/kind-of-blue/300x300bb.jpg")

        let requests = recorded.requests
        #expect(requests.count == 2)
        for request in requests {
            #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer dev-token")
            #expect(request.value(forHTTPHeaderField: "Music-User-Token") == "member-token")
            // The next page keeps the catalog matches the first asked for.
            let query = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems ?? []
            #expect(query.contains(URLQueryItem(name: "include", value: "catalog")))
        }
    }

    @Test("Playlists, albums, recently played and recommendations decode, skipping what HomePad cannot show")
    func decodesTheRest() async throws {
        let api = RecordedAppleMusic().api()

        let playlists = MemberMusicItem.list(try await api.library(.playlists, limit: 300))
        #expect(playlists.map(\.title) == ["Road Trip", "Pure Chill", "Dinner Party"])
        #expect(playlists.map(\.catalogID) == [nil, "pl.ce62a7a7f1a14a1aa8b0b04d5ad6ee08", "pl.u-8aAVXq7tbGZ1oY"])

        var snapshot = MemberMusicSnapshot()
        snapshot.set(MemberMusicItem.list(try await api.library(.albums, limit: 300)), for: .albums)
        #expect(snapshot.albums.map(\.catalogID) == ["268443092", nil, "617154241"])
        #expect(snapshot.recentlyAdded.map(\.title) == ["Garage Demos", "Kind of Blue", "Random Access Memories"])

        let recent = MemberMusicItem.list(try await api.recentlyPlayed())
        #expect(recent.map(\.title) == ["Rumours", "Road Trip", "Chill Station", "Kyle's Station"])
        #expect(recent.map(\.kind) == [.album, .playlist, .station, .station])

        let shelves = try await api.recommendations().compactMap(MemberMusicShelf.init)
        #expect(shelves.map(\.title) == ["Made for You", "New Releases for You"])
        #expect(shelves[0].items.first?.subtitle == "Apple Music for Kyle")
        #expect(shelves[1].items.map(\.catalogID) == ["1785123456", "1785123457"])
    }

    // MARK: What plays

    @Test("Only what the catalog has plays here. Their own playlists always open")
    func playableRule() async throws {
        let api = RecordedAppleMusic().api()
        let songs = MemberMusicItem.list(try await api.library(.songs, limit: 300))
        #expect(songs.map(\.isPlayable) == [true, false, true])
        #expect(songs[1].unavailableReason == "Not in Apple Music")

        let albums = MemberMusicItem.list(try await api.library(.albums, limit: 300))
        #expect(albums.first { $0.title == "Garage Demos" }?.unavailableReason == "Not in Apple Music")

        let playlists = MemberMusicItem.list(try await api.library(.playlists, limit: 300))
        let everyPlaylistPlays = playlists.allSatisfy { $0.isPlayable }
        #expect(everyPlaylistPlays)

        let recent = MemberMusicItem.list(try await api.recentlyPlayed())
        #expect(recent.first { $0.title == "Chill Station" }?.isPlayable == true)
        #expect(recent.first { $0.title == "Kyle's Station" }?.unavailableReason == "Only on its owner's account")

        let artist = MemberMusicItem(id: "r.1", kind: .artist, title: "Kyle", catalogID: nil, isLibrary: true)
        #expect(artist.unavailableReason == "Not in Apple Music")
    }

    @MainActor
    @Test("A playlist's page counts the songs that cannot play")
    func playlistSummary() {
        #expect(MemberMusicTiles.summary(songs: 3, playable: 3, duration: 600) == "3 Songs, 10 Min")
        #expect(MemberMusicTiles.summary(songs: 3, playable: 2, duration: 600)
            == "3 Songs, 10 Min. 1 song isn't in Apple Music and can't play here.")
    }

    // MARK: Tokens

    @Test("A 401 is tried again with a fresh developer token. A 403 means the member's token is turned down")
    func tokenFailures() async throws {
        let stale = RecordedAppleMusic()
        stale.statusByDeveloperToken = ["old": 401]
        let page = try await stale.api(developerTokens: ["old", "fresh"]).get("/v1/me/library/playlists", as: APIPage.self)
        #expect(page.data.count == 3)
        #expect(stale.requests.map { $0.value(forHTTPHeaderField: "Authorization") } == ["Bearer old", "Bearer fresh"])

        let turnedDown = RecordedAppleMusic()
        turnedDown.status = 403
        await #expect(throws: AppleMusicAPI.Failure.tokenRejected(403)) {
            try await turnedDown.api().library(.songs, limit: 300)
        }

        let stillUnauthorized = RecordedAppleMusic()
        stillUnauthorized.status = 401
        await #expect(throws: AppleMusicAPI.Failure.tokenRejected(401)) {
            try await stillUnauthorized.api().storefront()
        }
        #expect(stillUnauthorized.requests.count == 2)
    }

    @MainActor
    @Test("A turned-down token is reported once and the saved library keeps showing")
    func turnedDownTokenKeepsTheCache() async {
        let recorded = RecordedAppleMusic()
        recorded.status = 403
        var saved = MemberMusicSnapshot()
        saved.set([MemberMusicItem(id: "p.1", kind: .playlist, title: "Road Trip", isLibrary: true)], for: .playlists)
        saved.homeSavedAt = Date()
        var rejections = 0
        let library = MemberMusicLibrary(
            memberID: UUID(), memberName: "Kyle", link: MemberMusicLink(deviceID: "phone", deviceName: "Kyle's iPhone", linkedAt: Date()),
            snapshot: saved, api: recorded.api(), save: { _ in }, onRejected: { rejections += 1 }
        )
        await library.refreshHome()
        await library.load(.songs)

        #expect(rejections == 1)
        #expect(library.problem == .needsNewToken)
        #expect(library.snapshot.playlists.map(\.title) == ["Road Trip"])
        #expect(library.isHomeReady)
    }

    // MARK: Whose music shows

    @Test("Music shows a member's own Apple Music only while they are recognized and linked")
    func whoseLibraryShows() {
        let kyle = UUID()
        let sam = UUID()
        #expect(MemberAppleMusic.shownMember(unlocked: nil, linked: [kyle]) == nil)
        #expect(MemberAppleMusic.shownMember(unlocked: sam, linked: [kyle]) == nil)
        #expect(MemberAppleMusic.shownMember(unlocked: kyle, linked: [kyle, sam]) == kyle)
        #expect(MemberAppleMusic.shownMember(unlocked: kyle, linked: []) == nil)
    }

    @MainActor
    @Test("Picking someone in People does not show their library. Recognizing them does")
    func pickingIsNotEnough() throws {
        let services = AppServices(settings: SettingsStore(defaults: UserDefaults(suiteName: "audio.member.\(UUID())")!))
        let kyle = HouseholdMember(name: "Kyle", avatar: "🦊")
        services.household.add(kyle)
        let links = FakeMemberMusic()
        links.links = [kyle.id: MemberMusicLink(deviceID: "phone", deviceName: "Kyle's iPhone", linkedAt: Date())]
        services.memberMusic = links
        let music = MemberAppleMusic(services: services, isDemo: false)
        music.cache = MemberMusicCache(directory: FileManager.default.temporaryDirectory.appendingPathComponent("member-music-\(UUID())"),
                                       keychain: MemorySecretsForMusic())
        music.makeAPI = { RecordedAppleMusic().api(userToken: $0) }

        services.household.select(kyle.id)
        music.update()
        #expect(music.shown == nil)

        services.household.recognize(kyle.id)
        music.update()
        #expect(music.shown?.memberID == kyle.id)
        #expect(music.shown?.libraryTitle == "Kyle's Library")

        services.household.signOut()
        music.update()
        #expect(music.shown == nil)
    }

    // MARK: The assistant

    @Test("\"Play my playlist\" finds their own playlist by name")
    func myPlaylistMatching() {
        let playlists = ["Road Trip", "Road Trip Classics", "Café Mornings", "Workout"].map {
            MemberMusicItem(id: $0, kind: .playlist, title: $0, isLibrary: true)
        }
        #expect(MemberLibraryMatch.asksForOwnLibrary("play my playlist Road Trip"))
        #expect(MemberLibraryMatch.asksForOwnLibrary("the Workout playlist"))
        #expect(!MemberLibraryMatch.asksForOwnLibrary("Road Trip"))
        #expect(MemberLibraryMatch.playlist(for: "my playlist road trip", in: playlists)?.title == "Road Trip")
        #expect(MemberLibraryMatch.playlist(for: "my Road Trip playlist", in: playlists)?.title == "Road Trip")
        #expect(MemberLibraryMatch.playlist(for: "my cafe mornings", in: playlists)?.title == "Café Mornings")
        #expect(MemberLibraryMatch.playlist(for: "my classics playlist", in: playlists)?.title == "Road Trip Classics")
        #expect(MemberLibraryMatch.playlist(for: "my jazz playlist", in: playlists) == nil)
        #expect(MemberLibraryMatch.playlist(for: "my playlist", in: playlists) == nil)
    }

    // MARK: The encrypted cache

    @Test("Each member's cache is sealed with their own key and goes with it")
    func cacheSealsAndForgets() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("member-music-\(UUID())")
        let secrets = MemorySecretsForMusic()
        let cache = MemberMusicCache(directory: directory, keychain: secrets)
        let kyle = UUID()
        let sam = UUID()
        var snapshot = MemberMusicSnapshot()
        snapshot.set([MemberMusicItem(id: "p.1", kind: .playlist, title: "Road Trip", isLibrary: true)], for: .playlists)
        snapshot.keepTracks([MemberMusicItem(id: "i.1", kind: .song, title: "Blue in Green", catalogID: "268443097", isLibrary: true)],
                            of: "p.1")

        #expect(cache.save(snapshot, member: kyle))
        #expect(cache.save(MemberMusicSnapshot(), member: sam))
        #expect(cache.load(member: kyle) == snapshot)
        let file = try Data(contentsOf: directory.appendingPathComponent("\(kyle.uuidString).sealed"))
        #expect(file.range(of: Data("Road Trip".utf8)) == nil)

        cache.prune(keeping: [sam])
        #expect(cache.load(member: kyle) == nil)
        #expect(secrets.string(for: "key.\(kyle.uuidString)") == nil)
        #expect(cache.load(member: sam) != nil)
    }
}

/// A Connect stand-in that holds links in memory.
@MainActor
final class FakeMemberMusic: MemberMusicService {
    var links: [UUID: MemberMusicLink] = [:]
    private(set) var rejected: [UUID] = []
    func userToken(for member: UUID) -> String? { links[member] == nil ? nil : "member-token" }
    func tokenRejected(for member: UUID) { rejected.append(member) }
}

/// Keys in memory, so tests never touch the Keychain.
final class MemorySecretsForMusic: MemberMusicSecrets, @unchecked Sendable {
    private var values: [String: String] = [:]
    private let lock = NSLock()

    func string(for account: String) -> String? { lock.withLock { values[account] } }

    @discardableResult
    func set(_ value: String?, for account: String) -> Bool {
        lock.withLock { values[account] = value }
        return true
    }
}
