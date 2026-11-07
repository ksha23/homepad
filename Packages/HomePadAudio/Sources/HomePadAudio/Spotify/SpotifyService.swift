import AuthenticationServices
import Foundation
import HomePadCore
import Observation

/// Spotify as an optional third music source, through Spotify's Web API and
/// Spotify Connect. HomePad cannot play Spotify itself: iOS lets no app draw
/// or host another app, and Spotify's audio needs the Spotify app or a Connect
/// device. So HomePad browses, searches and controls, and the Spotify app on
/// this iPad plays by default. Its sound follows the iPad's AirPlay, so it
/// reaches the HomePods. Any other Connect device can be picked instead.
///
/// Each member can link their own Spotify account, and the household can link
/// one for guests (`SpotifyAccountBook`). While HomePad recognizes a member
/// with an account, everything here uses theirs (`owner`), else the
/// household's. Music that plays keeps its account until it stops.
///
/// Setup, once: a Spotify developer app with HomePad's redirect URI, its client
/// ID in Settings (kept in the keychain), and a sign-in, here or on a member's
/// own iPhone. Playback control needs Premium. Spotify's limits for personal
/// apps are in the README.
///
/// The rest is in extensions: `+Playback` (Now Playing, devices, this iPad,
/// transport, polling) and `+Library` (Listen Now, the library, search and pages).
@MainActor
@Observable
final class SpotifyService {
    /// Where the account in use stands, for Settings and the Music app.
    enum Status: Equatable {
        /// Turned off in Settings.
        case off
        case needsClientID
        /// No account is linked for whoever uses HomePad.
        case signedOut
        case signingIn
        case ready
        /// Signed in, but something needs the person (Premium, the user list, a new sign-in).
        case problem(SpotifyError)
    }

    /// The account in use: the recognized member's own, else the household's,
    /// nil when neither is linked (`SpotifyAccountChoice`).
    private(set) var owner: SpotifyAccountOwner?
    /// The account a sign-in on this iPad is for, while it runs.
    private(set) var signingIn: SpotifyAccountOwner?
    /// The last problem worth showing, cleared on the next success.
    var problem: SpotifyError?
    var playback: SpotifyPlayback?
    var devices: [SpotifyDevice] = []
    /// True once the device list was read, so "not open here" never shows before it is known.
    var hasReadDevices = false
    var home = SpotifyHome()
    var hasLoadedHome = false
    var isLoadingHome = false
    var searchResults: SpotifySearchResults?
    var isSearching = false
    /// The Library section's lists, by kind, once loaded.
    var library: [LibraryKind: [SpotifyItem]] = [:]
    var upNext: [SpotifyItem] = []
    /// Every linked account, with its record and whether it is signed in.
    let accounts: SpotifyAccountBook

    @ObservationIgnored let settings: SettingsStore
    @ObservationIgnored let keychain: KeychainStore
    /// The access token of the account in use.
    @ObservationIgnored var token: SpotifyToken?
    @ObservationIgnored var refreshTask: Task<SpotifyToken, Error>?
    /// Bumped whenever the account in use changes, so an answer that arrives
    /// after a switch is dropped instead of showing one person's music to another.
    @ObservationIgnored var accountEpoch = 0
    /// Sends requests to Spotify. Tests and the simulator demo answer themselves.
    @ObservationIgnored var load: SpotifyLoad = SpotifyLoader.network
    @ObservationIgnored var pollTask: Task<Void, Never>?
    /// Which poll loop is current, so an ended loop never clears a newer one.
    @ObservationIgnored var pollID = UUID()
    /// Screens showing Spotify now (`watch()`), which poll faster.
    @ObservationIgnored var watchers = 0
    @ObservationIgnored var lastPlayingAt: Date?
    /// True while Spotify is the music source, from the media service.
    @ObservationIgnored var isSelected: () -> Bool = { false }
    /// The member HomePad recognizes now, from the media service.
    @ObservationIgnored var recognizedMember: () -> UUID? = { nil }
    /// A member's name, for saying whose Spotify this iPad has.
    @ObservationIgnored var memberName: (UUID) -> String? = { _ in nil }
    /// The account in use changed. The media service reads Spotify again.
    @ObservationIgnored var onAccountChange: () -> Void = {}
    /// True while another app's audio plays on this iPad, which tells HomePad
    /// that a tablet Spotify plays on is this one (`SpotifyThisIPad`).
    @ObservationIgnored var otherAppPlaysHere: () -> Bool = { false }
    /// True while HomePad's own players play, from the media service.
    @ObservationIgnored var homePadPlays: () -> Bool = { false }
    /// The devices listed when HomePad opened Spotify here, until that wake ends.
    @ObservationIgnored var wakeBaseline: Set<String>?
    /// When Spotify last played on this iPad, to measure how long it stays a
    /// Connect device after it stops (in the audio trace).
    @ObservationIgnored var lastPlayingHereAt: Date?
    @ObservationIgnored var wasListedHere = false
    @ObservationIgnored let log = Log.make("Spotify")
    /// With `-HomePadAudioTrace YES`, when the Spotify app here joins and leaves Connect.
    @ObservationIgnored let trace = DebugTrace(file: "audio-session-trace.txt", argument: "HomePadAudioTrace")
    /// The household developer app's client ID, kept in the keychain.
    private(set) var clientID: String

    static let clientIDAccount = "audio.spotify.clientID"

    /// - Parameter secrets: Where refresh tokens are kept. This iPad's Keychain,
    ///   never synced, unless a test passes its own.
    init(settings: SettingsStore, keychain: KeychainStore, secrets: (any SpotifySecrets)? = nil) {
        var secrets = secrets ?? Self.tokenStore(for: keychain)
        var clientID = keychain.string(for: Self.clientIDAccount) ?? ""
        #if DEBUG
        if SpotifyDemo.isEnabled {
            secrets = SpotifyDemo.Secrets()
            clientID = SpotifyDemo.clientID
            settings[AudioSettings.spotifyEnabled] = true
        }
        #endif
        self.settings = settings
        self.keychain = keychain
        accounts = SpotifyAccountBook(settings: settings, secrets: secrets)
        self.clientID = clientID
        owner = SpotifyAccountChoice.wanted(recognized: nil, linked: accounts.owners)
        #if DEBUG
        if SpotifyDemo.isEnabled { load = SpotifyDemo.load }
        #endif
    }

    /// Refresh tokens stay in this iPad's Keychain and never sync: Spotify may
    /// replace one on each refresh, so a synced copy would sign the other device out.
    static func tokenStore(for keychain: KeychainStore) -> KeychainStore {
        KeychainStore(service: keychain.service, synchronizable: false)
    }

    var client: SpotifyClient {
        SpotifyClient(accessToken: { [weak self] in
            guard let self else { throw SpotifyError.signedOut }
            return try await self.validAccessToken()
        }, load: load)
    }

    // MARK: Status

    var isEnabled: Bool { settings[AudioSettings.spotifyEnabled] }

    /// True while the account in use has a refresh token on this iPad.
    var hasSignIn: Bool { owner.map(accounts.signedIn.contains) ?? false }

    /// The record of the account in use.
    var currentRecord: SpotifyAccountRecord? { owner.flatMap(accounts.record) }

    /// The name of the account in use, for Settings.
    var accountName: String? { currentRecord?.user?.name }

    /// True when Spotify is offered as a music source: it is on, and an
    /// account is linked for whoever uses HomePad.
    var isOffered: Bool { isEnabled && owner != nil }

    var status: Status {
        guard isEnabled else { return .off }
        if clientID.isEmpty { return .needsClientID }
        if let signingIn, signingIn == owner || owner == nil { return .signingIn }
        // Without Premium, browsing still works: that problem shows as a banner, not a setup state.
        if let problem, problem.needsSignIn || problem == .notAllowed { return .problem(problem) }
        guard let owner else { return .signedOut }
        return accounts.signedIn.contains(owner) ? .ready : .problem(.signedOut)
    }

    var isReady: Bool { status == .ready }

    /// Where the Spotify app on this iPad stands as a Connect device.
    enum HereState: Equatable {
        /// HomePad has not yet learned which device is this iPad.
        case unknown
        /// Learned, and not in the device list: closed, or asleep after it stopped.
        case notOpen
        case open
    }

    var hereState: HereState {
        guard thisIPadID != nil else { return .unknown }
        return thisIPad == nil ? .notOpen : .open
    }

    /// Saves the client ID from Settings. A new ID ends every sign-in made with
    /// the old one, so each account asks to sign in again.
    func setClientID(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed != clientID else { return }
        keychain.set(trimmed.isEmpty ? nil : trimmed, for: Self.clientIDAccount)
        clientID = trimmed
        accounts.forgetAllTokens()
        use(owner)
    }

    // MARK: The account in use

    /// Uses the account for whoever HomePad recognizes (`SpotifyAccountChoice`).
    /// Music from the account in use keeps it until it stops, unless someone
    /// starts new music (`startsNewMusic`).
    func followRecognizedMember(startsNewMusic: Bool = false) {
        let next = SpotifyAccountChoice.inUse(current: owner, wanted: wantedOwner, linked: accounts.owners,
                                              currentPlays: playback?.isPlaying == true, startsNewMusic: startsNewMusic)
        guard next != owner else { return }
        use(next)
    }

    /// The account for whoever HomePad recognizes now. It differs from `owner`
    /// while the last account's music plays on.
    var wantedOwner: SpotifyAccountOwner? {
        SpotifyAccountChoice.wanted(recognized: recognizedMember(), linked: accounts.owners)
    }

    /// The name of the account kept while its music plays, when HomePad
    /// recognizes someone else, for a line that says so.
    var keptForPlayingMusic: String? {
        guard let owner, owner != wantedOwner else { return nil }
        switch owner {
        case .household: return "the household's"
        case .member(let id): return memberName(id).map { "\($0)'s" }
        }
    }

    /// Switches to another account and forgets everything the last one showed.
    private func use(_ next: SpotifyAccountOwner?) {
        owner = next
        accountEpoch += 1
        token = nil
        refreshTask = nil
        pollTask?.cancel()
        pollTask = nil
        problem = nil
        playback = nil
        devices = []
        hasReadDevices = false
        home = SpotifyHome()
        hasLoadedHome = false
        searchResults = nil
        library = [:]
        upNext = []
        lastPlayingAt = nil
        lastPlayingHereAt = nil
        wasListedHere = false
        wakeBaseline = nil
        onAccountChange()
    }

    /// True while the account `epoch` was read for is still in use.
    func isCurrent(_ epoch: Int) -> Bool { epoch == accountEpoch }

    // MARK: Signing in

    /// Signs in on this iPad with a browser sheet, for `owner`. `authenticate`
    /// shows Spotify's page and returns the callback URL (SwiftUI's `webAuthenticationSession`).
    func signIn(for owner: SpotifyAccountOwner = .household, authenticate: (URL, String) async throws -> URL) async {
        guard !clientID.isEmpty else { problem = .notSetUp; return }
        signingIn = owner
        defer { signingIn = nil }
        let verifier = SpotifyAuth.makeVerifier()
        let state = UUID().uuidString
        do {
            let callback = try await authenticate(
                SpotifyAuth.authorizationURL(clientID: clientID, verifier: verifier, state: state), SpotifyAuth.callbackScheme)
            let code = try SpotifyAuth.code(from: callback, state: state)
            try await adopt(code: code, verifier: verifier, for: owner, signedInOn: nil)
        } catch let error as SpotifyError {
            problem = error
        } catch {
            // Closing the sheet is not a problem worth showing.
            if (error as? ASWebAuthenticationSessionError)?.code != .canceledLogin {
                problem = .signInFailed(error.localizedDescription)
            }
            log.error("Sign-in failed: \(String(reflecting: error), privacy: .public)")
        }
    }

    /// Exchanges a sign-in code for tokens and links them to `owner`: a code
    /// from a sign-in here, or one a member's iPhone handed over (`signedInOn`
    /// names the phone). Throws `.notAllowed` when Spotify knows the code but
    /// not the account, which stays linked so it works once added to the user list.
    @discardableResult
    func adopt(code: String, verifier: String, for owner: SpotifyAccountOwner, signedInOn: String?) async throws -> SpotifyAccountRecord {
        guard !clientID.isEmpty else { throw SpotifyError.notSetUp }
        let (data, response) = try await load(SpotifyAuth.tokenRequest(code: code, verifier: verifier, clientID: clientID))
        let token = try SpotifyAuth.token(from: data, status: (response as? HTTPURLResponse)?.statusCode ?? 0, previousRefreshToken: nil)
        // Who signed in, asked with the new token, whichever account is in use.
        var notAllowed = false
        var user: SpotifyUser?
        do {
            user = SpotifyUser(json: try await SpotifyClient(accessToken: { token.accessToken }, load: load).get("me"))
        } catch SpotifyError.notAllowed {
            notAllowed = true
        } catch {
            log.error("Reading the new account failed: \(String(reflecting: error), privacy: .public)")
        }
        var record = accounts.record(owner) ?? SpotifyAccountRecord()
        if record.user?.id != user?.id {
            // Another Spotify user: the device choice and this iPad's device were the old user's.
            record.deviceID = ""
            record.thisIPadID = nil
        }
        record.user = user ?? record.user
        record.signedInOn = signedInOn
        record.signedInAt = Date()
        accounts.link(owner, record: record, refreshToken: token.refreshToken)
        if self.owner == owner {
            use(owner)
        } else {
            followRecognizedMember()
        }
        // The new access token serves the account at once when it is the one in use.
        if self.owner == owner { self.token = token }
        if notAllowed { throw SpotifyError.notAllowed }
        return record
    }

    /// Signs the household's account out on this iPad.
    func signOut() { signOut(.household) }

    /// Removes an account's refresh token and record from this iPad. The next
    /// account for whoever uses HomePad takes over at once.
    func signOut(_ owner: SpotifyAccountOwner) {
        accounts.remove(owner)
        if self.owner == owner { use(wantedOwner) }
    }

    // MARK: Tokens

    /// The access token of the account in use, refreshed a minute before it
    /// runs out. One refresh at a time. A refresh that ends after a switch
    /// keeps its new refresh token for its own account and is not used.
    func validAccessToken() async throws -> String {
        guard let owner else { throw SpotifyError.signedOut }
        if let token, !token.needsRefresh() { return token.accessToken }
        guard let refreshToken = token?.refreshToken ?? accounts.refreshToken(for: owner) else {
            throw SpotifyError.signedOut
        }
        guard !clientID.isEmpty else { throw SpotifyError.notSetUp }
        if let refreshTask { return try await refreshTask.value.accessToken }
        let clientID = clientID
        let load = load
        let task = Task<SpotifyToken, Error> {
            let (data, response) = try await load(SpotifyAuth.refreshRequest(refreshToken: refreshToken, clientID: clientID))
            return try SpotifyAuth.token(from: data, status: (response as? HTTPURLResponse)?.statusCode ?? 0,
                                         previousRefreshToken: refreshToken)
        }
        refreshTask = task
        defer { if refreshTask == task { refreshTask = nil } }
        do {
            let fresh = try await task.value
            if fresh.refreshToken != refreshToken { accounts.keep(refreshToken: fresh.refreshToken, for: owner) }
            guard self.owner == owner else { throw CancellationError() }
            token = fresh
            return fresh.accessToken
        } catch let error as SpotifyError {
            if error.needsSignIn { accounts.forgetToken(of: owner) }
            if self.owner == owner {
                token = nil
                problem = error
            }
            throw error
        }
    }

    /// Reads the account's name again, in case it changed on Spotify.
    func loadAccount() async {
        let epoch = accountEpoch
        guard let owner, let me = try? await client.get("me"), isCurrent(epoch), let user = SpotifyUser(json: me) else { return }
        accounts.update(owner) { $0.user = user }
    }

    /// Runs a request and keeps its error for the screen.
    func perform(_ action: () async throws -> Void) async {
        do {
            try await action()
            problem = nil
        } catch let error as SpotifyError {
            problem = error
        } catch {
            problem = .http(0, error.localizedDescription)
        }
    }
}
