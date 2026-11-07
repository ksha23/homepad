import Foundation
import HomePadCore
import Testing
@testable import HomePadAudio

/// Spotify sign-in, requests and answers, in the shapes Spotify's Web API documents.
@MainActor @Suite struct SpotifyTests {
    private func json(_ text: String) -> JSONValue {
        (try? JSONValue.parse(text)) ?? .null
    }

    // MARK: Sign-in

    /// RFC 7636, appendix B.
    @Test func pkceChallengeMatchesTheStandardsExample() {
        #expect(SpotifyAuth.challenge(for: "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk") == "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM")
    }

    @Test func verifiersAreLongRandomAndUnreserved() {
        let first = SpotifyAuth.makeVerifier()
        #expect(first.count == 64)
        #expect(first != SpotifyAuth.makeVerifier())
        #expect(first.allSatisfy { $0.isLetter || $0.isNumber || "-._~".contains($0) })
    }

    @Test func authorizationURLAsksForCodeWithPKCE() throws {
        let url = SpotifyAuth.authorizationURL(clientID: "abc123", verifier: "verifier", state: "xyz")
        let items = Dictionary(uniqueKeysWithValues: (URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? [])
            .map { ($0.name, $0.value ?? "") })
        #expect(url.host() == "accounts.spotify.com")
        #expect(items["client_id"] == "abc123")
        #expect(items["response_type"] == "code")
        #expect(items["redirect_uri"] == "homepad-spotify-login://callback")
        #expect(items["code_challenge_method"] == "S256")
        #expect(items["code_challenge"] == SpotifyAuth.challenge(for: "verifier"))
        #expect(items["state"] == "xyz")
        #expect(items["scope"]?.contains("user-modify-playback-state") == true)
    }

    @Test func callbackGivesTheCodeOnlyForThisSignIn() throws {
        let good = URL(string: "homepad-spotify-login://callback?code=AQB&state=xyz")!
        #expect(try SpotifyAuth.code(from: good, state: "xyz") == "AQB")
        #expect(throws: SpotifyError.self) { try SpotifyAuth.code(from: good, state: "other") }
        let denied = URL(string: "homepad-spotify-login://callback?error=access_denied&state=xyz")!
        #expect(throws: SpotifyError.signInFailed("Spotify sign-in was canceled.")) { try SpotifyAuth.code(from: denied, state: "xyz") }
    }

    @Test func tokenRequestsAreFormsWithTheVerifier() throws {
        let request = SpotifyAuth.tokenRequest(code: "AQB", verifier: "v~1", clientID: "abc")
        let body = String(decoding: request.httpBody ?? Data(), as: UTF8.self)
        #expect(request.httpMethod == "POST")
        #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/x-www-form-urlencoded")
        #expect(body.contains("grant_type=authorization_code"))
        #expect(body.contains("code_verifier=v~1"))
        #expect(body.contains("redirect_uri=homepad-spotify-login%3A%2F%2Fcallback"))
        let refresh = String(decoding: SpotifyAuth.refreshRequest(refreshToken: "R", clientID: "abc").httpBody ?? Data(), as: UTF8.self)
        #expect(refresh == "client_id=abc&grant_type=refresh_token&refresh_token=R")
    }

    @Test func tokensKeepTheOldRefreshTokenWhenNoNewOneComes() throws {
        let now = Date(timeIntervalSince1970: 1000)
        let data = Data(#"{"access_token":"A2","token_type":"Bearer","expires_in":3600}"#.utf8)
        let token = try SpotifyAuth.token(from: data, status: 200, previousRefreshToken: "R1", now: now)
        #expect(token == SpotifyToken(accessToken: "A2", refreshToken: "R1", expiresAt: now.addingTimeInterval(3600)))
        #expect(!token.needsRefresh(at: now.addingTimeInterval(3000)))
        #expect(token.needsRefresh(at: now.addingTimeInterval(3550)))
    }

    /// Spotify ends a sign-in after six months with `invalid_grant`.
    @Test func expiredSignInsAskForANewOne() {
        let data = Data(#"{"error":"invalid_grant","error_description":"Refresh token revoked"}"#.utf8)
        #expect(throws: SpotifyError.signInExpired) { try SpotifyAuth.token(from: data, status: 400, previousRefreshToken: "R") }
        #expect(SpotifyError.signInExpired.needsSignIn)
        #expect(!SpotifyError.noActiveDevice.needsSignIn)
    }

    // MARK: Requests and errors

    @Test func requestsCarryTheTokenAndQuery() {
        let request = SpotifyClient.request("PUT", "me/player/volume", query: ["volume_percent": "40", "device_id": "d1"], token: "T")
        #expect(request.url?.absoluteString == "https://api.spotify.com/v1/me/player/volume?device_id=d1&volume_percent=40")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer T")
        #expect(request.value(forHTTPHeaderField: "Content-Length") == "0")
        let play = SpotifyClient.request("PUT", "me/player/play", body: ["context_uri": "spotify:album:1"], token: "T")
        #expect(play.value(forHTTPHeaderField: "Content-Type") == "application/json")
        #expect(String(decoding: play.httpBody ?? Data(), as: UTF8.self).contains("spotify:album:1"))
    }

    @Test func errorsSayWhatToDo() {
        func error(_ status: Int, _ body: String) -> SpotifyError { SpotifyClient.error(status: status, data: Data(body.utf8)) }
        #expect(error(403, #"{"error":{"status":403,"message":"Player command failed: Premium required","reason":"PREMIUM_REQUIRED"}}"#) == .needsPremium)
        #expect(error(404, #"{"error":{"status":404,"message":"Player command failed: No active device found","reason":"NO_ACTIVE_DEVICE"}}"#) == .noActiveDevice)
        #expect(error(403, #"{"error":{"status":403,"message":"User not registered in the Developer Dashboard"}}"#) == .notAllowed)
        #expect(error(401, #"{"error":{"status":401,"message":"The access token expired"}}"#) == .signedOut)
        #expect(error(429, "") == .rateLimited)
        #expect(error(500, #"{"error":{"status":500,"message":"Server error"}}"#) == .http(500, "Server error"))
    }

    // MARK: Answers

    @Test func playbackReadsTheTrackDeviceAndModes() {
        let readAt = Date(timeIntervalSince1970: 100)
        let playback = SpotifyPlayback(json: json("""
        {"device":{"id":"d1","is_active":true,"is_restricted":false,"name":"Kitchen","type":"Speaker","volume_percent":35,"supports_volume":true},
         "shuffle_state":true,"repeat_state":"context","progress_ms":60000,"is_playing":true,
         "context":{"type":"album","uri":"spotify:album:al1"},
         "item":{"type":"track","id":"t1","uri":"spotify:track:t1","name":"Song","duration_ms":200000,
                 "artists":[{"name":"One"},{"name":"Two"}],
                 "album":{"id":"al1","name":"Album","images":[{"url":"https://i.scdn.co/big","width":640,"height":640},{"url":"https://i.scdn.co/small","width":64,"height":64}]},
                 "external_urls":{"spotify":"https://open.spotify.com/track/t1"}}}
        """), readAt: readAt)
        #expect(playback?.item?.name == "Song")
        #expect(playback?.item?.subtitle == "One and Two")
        #expect(playback?.item?.imageURL?.absoluteString == "https://i.scdn.co/big")
        #expect(playback?.item?.albumID == "al1")
        #expect(playback?.device?.name == "Kitchen")
        #expect(playback?.device?.volume == 0.35)
        #expect(playback?.isShuffled == true)
        #expect(playback?.repeatMode == .all)
        #expect(playback?.contextURI == "spotify:album:al1")
        // The position moves on between readings, up to the song's end.
        #expect(playback?.elapsed(at: readAt.addingTimeInterval(10)) == 70)
        #expect(playback?.elapsed(at: readAt.addingTimeInterval(500)) == 200)
        let nowPlaying = playback?.nowPlaying(at: readAt)
        #expect(nowPlaying?.title == "Song" && nowPlaying?.album == "Album" && nowPlaying?.outputName == "Kitchen")
    }

    @Test func nothingPlayingReadsAsNoPlayback() {
        #expect(SpotifyPlayback(json: .null) == nil)
    }

    @Test func repeatStatesMapBothWays() {
        for mode in MusicRepeatMode.allCases {
            var playback = SpotifyPlayback(json: json(#"{"is_playing":false}"#))!
            playback.repeatState = SpotifyPlayback.repeatState(for: mode)
            #expect(playback.repeatMode == mode)
        }
    }

    @Test func devicesListWithoutBrokenEntries() {
        let devices = SpotifyDevice.list(json("""
        {"devices":[{"id":"a","is_active":false,"name":"Kyle's iPhone","type":"Smartphone","volume_percent":50},
                    {"name":"No ID"},
                    {"id":"b","is_active":true,"name":"Office","type":"Speaker","supports_volume":false}]}
        """))
        #expect(devices.map(\.name) == ["Kyle's iPhone", "Office"])
        #expect(devices[0].systemImage == "iphone")
        #expect(devices[1].volume == nil)
    }

    @Test func listsUnwrapSavedItemsAndSkipNulls() {
        let albums = SpotifyItem.list(json("""
        [{"added_at":"2026-01-01T00:00:00Z","album":{"type":"album","id":"a1","uri":"spotify:album:a1","name":"Saved","artists":[{"name":"Band"}],"images":[]}},
         null]
        """), unwrapping: ["album"])
        #expect(albums.map(\.name) == ["Saved"])
        #expect(albums.first?.kind == .album)
        let playlist = SpotifyItem(json: json(#"{"type":"playlist","id":"p1","uri":"spotify:playlist:p1","name":"Mix","owner":{"display_name":"Kyle"},"images":null}"#))
        #expect(playlist?.subtitle == "Kyle")
        #expect(playlist?.imageURL == nil)
        // February 2026 playlist items use `item`, older ones `track`.
        let items = SpotifyItem.list(json("""
        [{"item":{"type":"track","id":"t1","uri":"spotify:track:t1","name":"New Shape"}},
         {"track":{"type":"track","id":"t2","uri":"spotify:track:t2","name":"Old Shape"}}]
        """), unwrapping: ["item", "track"])
        #expect(items.map(\.name) == ["New Shape", "Old Shape"])
    }

    @Test func searchResultsReadEveryKind() {
        let results = SpotifySearchResults(json: json("""
        {"tracks":{"items":[{"type":"track","id":"t","uri":"spotify:track:t","name":"T"}]},
         "artists":{"items":[{"type":"artist","id":"a","uri":"spotify:artist:a","name":"A"}]},
         "albums":{"items":[]},
         "playlists":{"items":[null,{"type":"playlist","id":"p","uri":"spotify:playlist:p","name":"P"}]}}
        """))
        #expect(results.tracks.map(\.name) == ["T"])
        #expect(results.artists.map(\.name) == ["A"])
        #expect(results.playlists.map(\.name) == ["P"])
        #expect(!results.isEmpty)
    }

    @Test func recentlyPlayedEntriesOpenTheirPage() {
        let item = SpotifyItem(kind: .playlist, id: "p1", name: "Mix")
        let recent = item.recent
        #expect(recent.itemID == "spotify:playlist:p1")
        #expect(SpotifyItem(recent: recent)?.id == "p1")
        #expect(SpotifyItem(recent: SpotifyItem(kind: .track, id: "t", name: "T").recent) == nil)
    }

    // MARK: Polling

    /// An always-on iPad asks Spotify only while it matters.
    @Test func pollsOnlyWhileSpotifyMatters() {
        let now = Date(timeIntervalSince1970: 10_000)
        #expect(SpotifyService.pollInterval(isActive: false, watchers: 1, isPlaying: true, lastPlayingAt: now, now: now) == nil)
        #expect(SpotifyService.pollInterval(isActive: true, watchers: 1, isPlaying: false, lastPlayingAt: nil, now: now) == 3)
        #expect(SpotifyService.pollInterval(isActive: true, watchers: 0, isPlaying: true, lastPlayingAt: now, now: now) == 15)
        #expect(SpotifyService.pollInterval(isActive: true, watchers: 0, isPlaying: false,
                                            lastPlayingAt: now.addingTimeInterval(-300), now: now) == 30)
        #expect(SpotifyService.pollInterval(isActive: true, watchers: 0, isPlaying: false,
                                            lastPlayingAt: now.addingTimeInterval(-900), now: now) == nil)
    }

    @Test func playlistDescriptionsLoseTheirHTML() {
        #expect(SpotifyService.plainText("Chill <a href=\"x\">beats</a> &amp; more") == "Chill beats & more")
    }

    /// Spotify shows up as a source only once it is turned on and an account
    /// is linked for whoever uses HomePad.
    @Test func spotifyIsASourceOnlyWhenTurnedOnWithAnAccount() {
        let settings = SettingsStore(defaults: UserDefaults(suiteName: "audio.spotify.\(UUID())")!)
        let services = AppServices(settings: settings)
        let media = AudioMediaService(services: services, isDemo: false)
        media.setMusicSource(.spotify)
        #expect(media.musicSource == .thisIPad)
        #expect(!media.availableMusicSources.contains(.spotify))
        settings[AudioSettings.spotifyEnabled] = true
        #expect(!media.availableMusicSources.contains(.spotify), "no account for anyone yet")
        // The household's account is linked (its record, as a launch finds it).
        settings[SpotifyAccountOwner.household.recordKey] = SpotifyAccountRecord()
        let linkedServices = AppServices(settings: settings)
        let linked = AudioMediaService(services: linkedServices, isDemo: false)
        #expect(linked.musicSource == .spotify)
        #expect(linked.availableMusicSources.contains(.spotify))
        #expect(linked.canChooseMusicSource)
        withExtendedLifetime(services) {}
        withExtendedLifetime(linkedServices) {}
    }
}
