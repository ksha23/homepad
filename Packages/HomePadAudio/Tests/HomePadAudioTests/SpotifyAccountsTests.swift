import Foundation
import HomePadCore
import Testing
@testable import HomePadAudio

/// Each member's own Spotify account: which account is in use for whom, that
/// music keeps its account until it stops, where the secrets live and when
/// they go, a sign-in handed over from a phone, and where music can play.
@MainActor @Suite struct SpotifyAccountsTests {
    private let kyle = UUID()
    private let sam = UUID()

    /// Refresh tokens in memory, so tests never touch the Keychain.
    final class MemorySecrets: SpotifySecrets {
        var values: [String: String] = [:]
        func string(for account: String) -> String? { values[account] }
        @discardableResult func set(_ value: String?, for account: String) -> Bool {
            values[account] = value
            return true
        }
    }

    private func freshSettings() -> SettingsStore {
        SettingsStore(defaults: UserDefaults(suiteName: "audio.spotify.accounts.\(UUID())")!)
    }

    private func makeService(_ settings: SettingsStore, _ secrets: MemorySecrets) -> SpotifyService {
        SpotifyService(settings: settings, keychain: KeychainStore(service: "test.\(UUID())", synchronizable: false), secrets: secrets)
    }

    private func device(_ id: String, _ type: String = "Smartphone", active: Bool = false) -> SpotifyDevice {
        SpotifyDevice(json: try? JSONValue.parse(#"{"id":"\#(id)","name":"\#(id)","type":"\#(type)","is_active":\#(active)}"#))!
    }

    private func playback(playing: Bool) -> SpotifyPlayback? {
        SpotifyPlayback(json: (try? JSONValue.parse(
            #"{"is_playing":\#(playing),"item":{"type":"track","id":"t1","uri":"spotify:track:t1","name":"Song"},"device":{"id":"phone","name":"Phone","type":"Smartphone"}}"#
        )) ?? .null)
    }

    // MARK: Which account

    @Test func aRecognizedMemberUsesTheirOwnAccountElseTheHouseholds() {
        let both: Set<SpotifyAccountOwner> = [.household, .member(kyle)]
        #expect(SpotifyAccountChoice.wanted(recognized: kyle, linked: both) == .member(kyle))
        #expect(SpotifyAccountChoice.wanted(recognized: sam, linked: both) == .household, "Sam has none")
        #expect(SpotifyAccountChoice.wanted(recognized: nil, linked: both) == .household)
        #expect(SpotifyAccountChoice.wanted(recognized: sam, linked: [.member(kyle)]) == nil, "no household account: Spotify is not offered")
        #expect(SpotifyAccountChoice.wanted(recognized: kyle, linked: [.member(kyle)]) == .member(kyle))
    }

    @Test func musicThatPlaysKeepsItsAccountUntilItStopsOrSomeoneStartsNewMusic() {
        let linked: Set<SpotifyAccountOwner> = [.household, .member(kyle)]
        func inUse(plays: Bool, starts: Bool = false, linked: Set<SpotifyAccountOwner> = linked) -> SpotifyAccountOwner? {
            SpotifyAccountChoice.inUse(current: .household, wanted: .member(kyle), linked: linked, currentPlays: plays, startsNewMusic: starts)
        }
        #expect(inUse(plays: true) == .household)
        #expect(inUse(plays: false) == .member(kyle))
        #expect(inUse(plays: true, starts: true) == .member(kyle))
        #expect(inUse(plays: true, linked: [.member(kyle)]) == .member(kyle), "a signed-out account is not kept")
    }

    @Test func theServiceSwitchesAccountsAndForgetsWhatTheLastOneShowed() {
        let settings = freshSettings()
        let spotify = makeService(settings, MemorySecrets())
        spotify.accounts.link(.household, record: SpotifyAccountRecord(user: SpotifyUser(id: "home", name: "Home")), refreshToken: "H")
        spotify.accounts.link(.member(kyle), record: SpotifyAccountRecord(user: SpotifyUser(id: "kyle", name: "kyle_s")), refreshToken: "K")
        var recognized: UUID?
        spotify.recognizedMember = { recognized }
        var changes = 0
        spotify.onAccountChange = { changes += 1 }
        spotify.followRecognizedMember()
        #expect(spotify.owner == .household)
        #expect(changes == 1, "from no account to the household's")

        recognized = kyle
        spotify.followRecognizedMember()
        #expect(spotify.owner == .member(kyle))
        #expect(spotify.accountName == "kyle_s")
        #expect(changes == 2)

        // Kyle's music plays and Sam steps up: Kyle's stays until it stops.
        spotify.playback = playback(playing: true)
        spotify.home.playlists = [SpotifyItem(json: try? JSONValue.parse(#"{"type":"playlist","id":"p","uri":"spotify:playlist:p","name":"Kyle's Mix"}"#))!]
        recognized = sam
        spotify.followRecognizedMember()
        #expect(spotify.owner == .member(kyle))
        #expect(spotify.keptForPlayingMusic == nil, "no member names are known yet")
        spotify.memberName = { $0 == self.kyle ? "Kyle" : "Sam" }
        #expect(spotify.keptForPlayingMusic == "Kyle's")

        spotify.playback = playback(playing: false)
        spotify.followRecognizedMember()
        #expect(spotify.owner == .household)
        #expect(spotify.home.isEmpty, "nothing of Kyle's shows to Sam")
        #expect(spotify.playback == nil)
        #expect(changes == 3)
    }

    // MARK: Secrets

    @Test func refreshTokensStayInThisIPadsKeychainAndGoWithTheMember() {
        #expect(!SpotifyService.tokenStore(for: KeychainStore()).synchronizable, "never iCloud Keychain")
        let suite = "audio.spotify.secrets.\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        let settings = SettingsStore(defaults: defaults)
        let secrets = MemorySecrets()
        let spotify = makeService(settings, secrets)
        spotify.accounts.link(.member(kyle), record: SpotifyAccountRecord(user: SpotifyUser(id: "kyle", name: "kyle_s")), refreshToken: "secret-K")
        spotify.accounts.link(.member(sam), record: SpotifyAccountRecord(), refreshToken: "secret-S")
        #expect(secrets.values[SpotifyAccountOwner.member(kyle).refreshTokenAccount] == "secret-K")
        // Settings hold the record, never the token.
        let stored = defaults.dictionaryRepresentation().values.compactMap { ($0 as? Data).map { String(decoding: $0, as: UTF8.self) } }
        #expect(!stored.contains { $0.contains("secret-") })
        #expect(settings[SpotifyAccountBook.membersKey].count == 2)

        // A new launch finds both.
        let again = makeService(settings, secrets)
        #expect(again.accounts.signedIn == [.member(kyle), .member(sam)])

        // Kyle leaves the household: his token and record go at once.
        again.accounts.prune(keeping: [sam])
        #expect(secrets.values[SpotifyAccountOwner.member(kyle).refreshTokenAccount] == nil)
        #expect(settings[SpotifyAccountOwner.member(kyle).recordKey] == nil)
        #expect(settings[SpotifyAccountBook.membersKey] == [sam])

        // Sam signs out.
        again.signOut(.member(sam))
        #expect(secrets.values.isEmpty)
        #expect(again.accounts.owners.isEmpty)
    }

    @Test func anEndedSignInKeepsItsRecordAndAsksAgain() {
        let spotify = makeService(freshSettings(), MemorySecrets())
        spotify.accounts.link(.household, record: SpotifyAccountRecord(), refreshToken: "H")
        spotify.accounts.forgetToken(of: .household)
        #expect(spotify.accounts.needsSignInAgain(.household))
        spotify.followRecognizedMember()
        #expect(spotify.owner == .household, "still offered, so it can say to sign in again")
    }

    @Test func aSignInMadeBeforeMembersHadAccountsBecomesTheHouseholds() {
        let settings = freshSettings()
        let secrets = MemorySecrets()
        secrets.values["audio.spotify.refreshToken"] = "old"
        settings[AudioSettings.spotifyDeviceID] = "kitchen"
        settings[AudioSettings.spotifyThisIPadID] = "here"
        let spotify = makeService(settings, secrets)
        #expect(spotify.owner == .household)
        #expect(spotify.currentRecord?.deviceID == "kitchen")
        #expect(spotify.thisIPadID == "here")
        #expect(settings[AudioSettings.spotifyDeviceID].isEmpty)
    }

    // MARK: A sign-in from a member's phone

    @Test func aCodeFromKylesPhoneBecomesKylesAccountOnly() async throws {
        let settings = freshSettings()
        settings[AudioSettings.spotifyEnabled] = true
        let secrets = MemorySecrets()
        let spotify = makeService(settings, secrets)
        spotify.setClientID("0123456789abcdef0123456789abcdef")
        spotify.accounts.link(.household, record: SpotifyAccountRecord(user: SpotifyUser(id: "home", name: "Home")), refreshToken: "H")
        spotify.followRecognizedMember()
        let asked = RequestLog()
        spotify.load = { request in
            await asked.add(request)
            let isToken = request.url?.host() == "accounts.spotify.com"
            let body = isToken ? #"{"access_token":"A","refresh_token":"R-kyle","expires_in":3600}"# : #"{"id":"kyle","display_name":"kyle_s"}"#
            return (Data(body.utf8), HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }
        let record = try await spotify.adopt(code: "AQB", verifier: "v", for: .member(kyle), signedInOn: "Kyle's iPhone")
        #expect(record.user?.name == "kyle_s")
        #expect(record.signedInOn == "Kyle's iPhone")
        #expect(secrets.values[SpotifyAccountOwner.member(kyle).refreshTokenAccount] == "R-kyle")
        #expect(secrets.values[SpotifyAccountOwner.household.refreshTokenAccount] == "H", "the household's stays as it was")
        #expect(spotify.owner == .household, "Kyle is not recognized, so the household's stays in use")
        let form = String(decoding: await asked.requests.first?.httpBody ?? Data(), as: UTF8.self)
        #expect(form.contains("code=AQB") && form.contains("code_verifier=v"))

        spotify.recognizedMember = { self.kyle }
        spotify.followRecognizedMember()
        #expect(spotify.owner == .member(kyle))
        #expect(spotify.isReady)
    }

    // MARK: Where it plays

    @Test func musicPlaysOnThisIPadOnlyWhenItsSpotifyIsThisAccounts() {
        let phone = device("phone"), speaker = device("speaker", "Speaker")
        let active = device("phone", active: true)
        #expect(SpotifyTarget.choose(chosen: "", devices: [phone], playing: nil, thisIPadIsOthers: nil) == .thisIPad)
        #expect(SpotifyTarget.choose(chosen: "", devices: [active], playing: nil, thisIPadIsOthers: "Kyle") == .device(active))
        #expect(SpotifyTarget.choose(chosen: "", devices: [phone], playing: nil, thisIPadIsOthers: "Kyle") == .thisIPadIsOthers("Kyle"))
        #expect(SpotifyTarget.choose(chosen: "speaker", devices: [phone, speaker], playing: nil, thisIPadIsOthers: "Kyle") == .device(speaker))
        #expect(SpotifyTarget.choose(chosen: "speaker", devices: [active], playing: nil, thisIPadIsOthers: nil) == .device(active))
        #expect(SpotifyTarget.choose(chosen: "speaker", devices: [], playing: nil, thisIPadIsOthers: nil) == .noDevice)

        let kyleUser = SpotifyUser(id: "kyle", name: "kyle_s"), samUser = SpotifyUser(id: "sam", name: "sam")
        #expect(SpotifyAccountChoice.otherAccount(onThisIPad: kyleUser, inUse: samUser) == kyleUser)
        #expect(SpotifyAccountChoice.otherAccount(onThisIPad: kyleUser, inUse: SpotifyUser(id: "kyle", name: "Kyle again")) == nil)
        #expect(SpotifyAccountChoice.otherAccount(onThisIPad: nil, inUse: samUser) == nil, "not seen yet")
    }

    @Test func samIsToldThisIPadsSpotifyIsKyles() async {
        let spotify = makeService(freshSettings(), MemorySecrets())
        spotify.memberName = { $0 == self.kyle ? "Kyle" : "Sam" }
        spotify.accounts.link(.member(kyle), record: SpotifyAccountRecord(user: SpotifyUser(id: "kyle", name: "kyle_s"), thisIPadID: "ipad"),
                              refreshToken: "K")
        spotify.accounts.link(.member(sam), record: SpotifyAccountRecord(user: SpotifyUser(id: "sam", name: "sam")), refreshToken: "S")
        // HomePad saw the iPad's Spotify app in Kyle's device list.
        var recognized = kyle
        spotify.recognizedMember = { recognized }
        spotify.followRecognizedMember()
        spotify.devices = [device("ipad", "Tablet")]
        spotify.learnThisIPad()
        #expect(spotify.accounts.thisIPadUser?.id == "kyle")
        #expect(spotify.targetsThisIPad)

        recognized = sam
        spotify.followRecognizedMember()
        #expect(spotify.thisIPadIsOthers == "Kyle")
        #expect(!spotify.targetsThisIPad)
        #expect(spotify.target == .thisIPadIsOthers("Kyle"))
        await #expect(throws: SpotifyError.thisIPadIsOthers("Kyle")) { try await spotify.play(uri: "spotify:album:a") }
        // Sam's own phone is on: it plays there.
        spotify.devices = [device("sam-phone", active: true)]
        #expect(spotify.targetDevice?.id == "sam-phone")
    }

    // MARK: Music Assistant

    @Test func musicAssistantRequestsNameTheMembersUserOnlyWhenSet() {
        let search = MusicAssistantAction.search(entryID: "e", query: "jazz", username: "sam")
        #expect(search.data["username"]?.stringValue == "sam")
        #expect(MusicAssistantAction.search(entryID: "e", query: "jazz").data["username"] == nil, "older Home Assistant refuses unknown fields")
        #expect(MusicAssistantAction.library(entryID: "e", mediaType: .album, username: "sam").data["username"]?.stringValue == "sam")
        #expect(MusicAssistantAction.playMedia(entityID: "media_player.kitchen", mediaIDs: ["x"], username: "").data["username"] == nil)
        let member = HouseholdMember(name: "Sam", preferences: [AudioSettings.musicAssistantUserPreference: .string(" sam ")])
        #expect(AudioMediaService.musicAssistantUser(of: member) == "sam")
        #expect(AudioMediaService.musicAssistantUser(of: HouseholdMember(name: "Kyle")) == nil)
    }
}

/// Requests a fake Spotify answered, in order.
actor RequestLog {
    private(set) var requests: [URLRequest] = []
    func add(_ request: URLRequest) { requests.append(request) }
}
