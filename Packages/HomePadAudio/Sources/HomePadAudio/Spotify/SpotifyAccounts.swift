import Foundation
import HomePadCore
import Observation

/// Whose Spotify account: the household's, or one member's own.
enum SpotifyAccountOwner: Hashable, Sendable {
    case household
    case member(UUID)

    var memberID: UUID? {
        if case .member(let id) = self { return id }
        return nil
    }

    /// Its refresh token's account in this iPad's Keychain. The household's
    /// keeps the name it had before members had their own, so a sign-in made
    /// then still works.
    var refreshTokenAccount: String {
        switch self {
        case .household: "audio.spotify.refreshToken"
        case .member(let id): "audio.spotify.refreshToken.\(id.uuidString)"
        }
    }

    /// Where its record is kept, in this iPad's settings only.
    var recordKey: SettingKey<SpotifyAccountRecord?> {
        switch self {
        case .household: SettingKey("audio.spotify.account", default: nil)
        case .member(let id): SettingKey("audio.spotify.account.\(id.uuidString)", default: nil)
        }
    }
}

/// A Spotify user, from `GET /me`.
struct SpotifyUser: Codable, Hashable, Sendable {
    var id: String
    var name: String?

    init(id: String, name: String?) {
        self.id = id
        self.name = name
    }

    init?(json: JSONValue) {
        guard let id = json["id"]?.stringValue else { return nil }
        self.init(id: id, name: json["display_name"]?.stringValue ?? id)
    }
}

/// What this iPad keeps about one linked account besides its refresh token.
/// Nothing in it is secret, and it never leaves this iPad.
struct SpotifyAccountRecord: Codable, Equatable, Sendable {
    /// Who signed in, once Spotify said.
    var user: SpotifyUser?
    /// The phone they signed in on, nil for this iPad.
    var signedInOn: String?
    var signedInAt: Date
    /// The Connect device new music plays on. Empty means this iPad's Spotify app.
    var deviceID: String
    /// The Connect device ID of the Spotify app on this iPad under this account, once learned (`SpotifyThisIPad`).
    var thisIPadID: String?

    init(user: SpotifyUser? = nil, signedInOn: String? = nil, signedInAt: Date = Date(), deviceID: String = "", thisIPadID: String? = nil) {
        self.user = user
        self.signedInOn = signedInOn
        self.signedInAt = signedInAt
        self.deviceID = deviceID
        self.thisIPadID = thisIPadID
    }
}

/// Where refresh tokens live: this iPad's Keychain in the app, memory in tests.
protocol SpotifySecrets {
    func string(for account: String) -> String?
    @discardableResult func set(_ value: String?, for account: String) -> Bool
}

extension KeychainStore: SpotifySecrets {}

/// The Spotify accounts linked on this iPad: the household's and each member's.
///
/// - A refresh token per account sits in this iPad's Keychain, never iCloud
///   Keychain. Spotify may replace it on each refresh, so a synced copy would
///   sign the other device out. It is never logged.
/// - A record per account sits in this iPad's settings: who signed in, where,
///   the device new music plays on, and which Connect device this iPad is.
/// - An account whose token Spotify ended keeps its record, so it asks to sign
///   in again instead of falling silently to someone else's.
/// - Signing out, or the member leaving the household, removes both.
@MainActor
@Observable
final class SpotifyAccountBook {
    private(set) var records: [SpotifyAccountOwner: SpotifyAccountRecord] = [:]
    /// The accounts with a refresh token on this iPad.
    private(set) var signedIn: Set<SpotifyAccountOwner> = []
    /// Whose Spotify the Spotify app on this iPad was signed in to when HomePad
    /// last saw it in an account's device list.
    private(set) var thisIPadUser: SpotifyUser?

    @ObservationIgnored private let settings: SettingsStore
    @ObservationIgnored private let secrets: any SpotifySecrets

    /// The members with a record, so a member removed while HomePad was not running is still found.
    static let membersKey = SettingKey<[UUID]>("audio.spotify.members", default: [])
    static let thisIPadUserKey = SettingKey<SpotifyUser?>("audio.spotify.thisIPadUser", default: nil)

    init(settings: SettingsStore, secrets: any SpotifySecrets) {
        self.settings = settings
        self.secrets = secrets
        thisIPadUser = settings[Self.thisIPadUserKey]
        let owners = [SpotifyAccountOwner.household] + settings[Self.membersKey].map(SpotifyAccountOwner.member)
        for owner in owners {
            if let record = settings[owner.recordKey] { records[owner] = record }
            if secrets.string(for: owner.refreshTokenAccount) != nil { signedIn.insert(owner) }
        }
        adoptSingleAccountSignIn()
    }

    /// A household sign-in made before members had accounts has a token and
    /// no record. Its device choice and this iPad's device move into one.
    private func adoptSingleAccountSignIn() {
        guard records[.household] == nil, signedIn.contains(.household) else { return }
        let device = settings[AudioSettings.spotifyDeviceID]
        let here = settings[AudioSettings.spotifyThisIPadID]
        save(SpotifyAccountRecord(deviceID: device, thisIPadID: here.isEmpty ? nil : here), for: .household)
        settings.reset(AudioSettings.spotifyDeviceID)
        settings.reset(AudioSettings.spotifyThisIPadID)
    }

    /// The accounts linked on this iPad, signed in or waiting to sign in again.
    var owners: Set<SpotifyAccountOwner> { Set(records.keys) }

    func record(_ owner: SpotifyAccountOwner) -> SpotifyAccountRecord? { records[owner] }

    /// True when the account was linked and Spotify has since ended its sign-in.
    func needsSignInAgain(_ owner: SpotifyAccountOwner) -> Bool {
        records[owner] != nil && !signedIn.contains(owner)
    }

    /// The account a Spotify user is linked as, the household's first.
    func owner(of user: SpotifyUser) -> SpotifyAccountOwner? {
        if records[.household]?.user?.id == user.id { return .household }
        return records.first { $0.value.user?.id == user.id }?.key
    }

    // MARK: Tokens

    func refreshToken(for owner: SpotifyAccountOwner) -> String? {
        secrets.string(for: owner.refreshTokenAccount)
    }

    /// Keeps a new refresh token. Spotify may hand out a new one on refresh.
    func keep(refreshToken: String, for owner: SpotifyAccountOwner) {
        secrets.set(refreshToken, for: owner.refreshTokenAccount)
        signedIn.insert(owner)
    }

    /// Spotify ended the sign-in. The record stays, so the account asks to sign in again.
    func forgetToken(of owner: SpotifyAccountOwner) {
        secrets.set(nil, for: owner.refreshTokenAccount)
        signedIn.remove(owner)
    }

    /// A new client ID ends every sign-in made with the old one.
    func forgetAllTokens() {
        for owner in signedIn { secrets.set(nil, for: owner.refreshTokenAccount) }
        signedIn = []
    }

    // MARK: Records

    /// Links an account: its record and its refresh token.
    func link(_ owner: SpotifyAccountOwner, record: SpotifyAccountRecord, refreshToken: String) {
        keep(refreshToken: refreshToken, for: owner)
        save(record, for: owner)
    }

    func update(_ owner: SpotifyAccountOwner, _ change: (inout SpotifyAccountRecord) -> Void) {
        guard var record = records[owner] else { return }
        change(&record)
        guard record != records[owner] else { return }
        save(record, for: owner)
    }

    /// Signs the account out on this iPad: its token and its record.
    func remove(_ owner: SpotifyAccountOwner) {
        secrets.set(nil, for: owner.refreshTokenAccount)
        signedIn.remove(owner)
        let user = records.removeValue(forKey: owner)?.user
        settings.reset(owner.recordKey)
        if let id = owner.memberID {
            settings[Self.membersKey] = settings[Self.membersKey].filter { $0 != id }
        }
        // The name of someone who left is not kept for this iPad's Spotify app.
        if let user, thisIPadUser?.id == user.id, self.owner(of: user) == nil {
            thisIPadUser = nil
            settings.reset(Self.thisIPadUserKey)
        }
    }

    /// Removes the accounts of people no longer in the household.
    func prune(keeping members: Set<UUID>) {
        let gone = settings[Self.membersKey].filter { !members.contains($0) }
        for id in gone { remove(.member(id)) }
    }

    /// The Spotify app on this iPad showed up in this user's device list.
    func noteThisIPad(_ user: SpotifyUser) {
        guard thisIPadUser != user else { return }
        thisIPadUser = user
        settings[Self.thisIPadUserKey] = user
    }

    /// A person took the household's ID for them as this HomePad joined its
    /// setup: their account, its token and its device choice move to it, so
    /// they stay signed in.
    func moveMember(from old: UUID, to new: UUID) {
        let from = SpotifyAccountOwner.member(old)
        let to = SpotifyAccountOwner.member(new)
        guard let record = records[from], records[to] == nil else { return }
        let token = secrets.string(for: from.refreshTokenAccount)
        secrets.set(nil, for: from.refreshTokenAccount)
        signedIn.remove(from)
        records[from] = nil
        settings.reset(from.recordKey)
        settings[Self.membersKey] = settings[Self.membersKey].filter { $0 != old }
        if let token { keep(refreshToken: token, for: to) }
        save(record, for: to)
    }

    private func save(_ record: SpotifyAccountRecord, for owner: SpotifyAccountOwner) {
        records[owner] = record
        settings[owner.recordKey] = record
        if let id = owner.memberID, !settings[Self.membersKey].contains(id) {
            settings[Self.membersKey] = settings[Self.membersKey] + [id]
        }
    }
}

/// Which account Spotify uses, for whoever HomePad recognizes. Pure, so it is tested.
enum SpotifyAccountChoice {
    /// A recognized member's own account, else the household's, else none.
    /// A member who has none uses the household's.
    static func wanted(recognized: UUID?, linked: Set<SpotifyAccountOwner>) -> SpotifyAccountOwner? {
        if let recognized, linked.contains(.member(recognized)) { return .member(recognized) }
        return linked.contains(.household) ? .household : nil
    }

    /// The account to use now. Music that plays keeps its account, so whoever
    /// started it can still pause it, as Apple Music keeps its queue for them.
    /// The switch waits until it stops, or until someone starts new music.
    static func inUse(current: SpotifyAccountOwner?, wanted: SpotifyAccountOwner?, linked: Set<SpotifyAccountOwner>,
                      currentPlays: Bool, startsNewMusic: Bool) -> SpotifyAccountOwner? {
        guard let current, current != wanted, linked.contains(current), currentPlays, !startsNewMusic else { return wanted }
        return current
    }

    /// Whose Spotify the Spotify app on this iPad is signed in to, when that is
    /// not the account in use. Nil while it is the same user, or not known.
    static func otherAccount(onThisIPad: SpotifyUser?, inUse: SpotifyUser?) -> SpotifyUser? {
        guard let onThisIPad, let inUse, onThisIPad.id != inUse.id else { return nil }
        return onThisIPad
    }
}
