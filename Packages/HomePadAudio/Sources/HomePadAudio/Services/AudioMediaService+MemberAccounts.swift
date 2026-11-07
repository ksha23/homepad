import Foundation
import HomePadCore

/// Each member's own music accounts: their Spotify account, and the Music
/// Assistant user their requests go to.
///
/// - Spotify uses the account of the member HomePad recognizes (`unlockedMember`),
///   else the household's. Picking someone by hand in People is not enough, as
///   for their messages and photos (`SpotifyAccountChoice`).
/// - A member removed from the household loses their Spotify sign-in on this
///   iPad at once, token and record.
/// - On the HomePad, a member's own iPhone hands over a Spotify sign-in made
///   there (`SpotifyMemberAccounts`, called by the Connect module).
extension AudioMediaService: SpotifyMemberAccounts {
    /// Gives the Spotify service who HomePad recognizes. Called once from `init`.
    func wireMemberAccounts() {
        spotify.recognizedMember = { [weak self] in self?.services.household.unlockedMember?.id }
        spotify.memberName = { [weak self] id in self?.services.household.members.first { $0.id == id }?.name }
        spotify.onAccountChange = { [weak self] in self?.spotifyAccountDidChange() }
    }

    /// Follows who HomePad recognizes and who is in the household. Called once
    /// from `start()`, then on every change.
    func trackMemberAccounts() {
        let (members, user) = withObservationTracking {
            (Set(services.household.members.map(\.id)), Self.musicAssistantUser(of: services.household.unlockedMember))
        } onChange: { [weak self] in
            Task { @MainActor in self?.trackMemberAccounts() }
        }
        spotify.accounts.prune(keeping: members)
        #if DEBUG
        SpotifyDemo.seed(spotify, members: services.household.members)
        #endif
        spotify.followRecognizedMember()
        musicAssistant.use(user: user)
    }

    /// The account in use changed: pages of the last account's music close, and
    /// Spotify is read again while it is the source.
    func spotifyAccountDidChange() {
        if pages.pages.contains(where: \.isSpotify) { pages.popToRoot() }
        guard musicSource == .spotify else { return }
        Task { await refreshSpotify() }
    }

    /// New music belongs to whoever starts it. When HomePad recognizes someone
    /// whose account is not the one in use, theirs takes over first, and what
    /// the last account played on this iPad pauses, so two never play here.
    func useSpotifyAccountForNewMusic() async {
        guard spotify.wantedOwner != spotify.owner else { return }
        if spotify.playback?.isPlaying == true, spotify.playsHere { try? await spotify.pause() }
        spotify.followRecognizedMember(startsNewMusic: true)
        // Where the new account can play must be known before it plays.
        async let devices: Void = spotify.refreshDevices()
        async let playback: Void = spotify.refreshPlayback()
        _ = await (devices, playback)
    }

    // MARK: Music Assistant

    /// The Music Assistant user a member's requests go to, from their preferences.
    static func musicAssistantUser(of member: HouseholdMember?) -> String? {
        guard let name = member?.preferences[AudioSettings.musicAssistantUserPreference]?.stringValue?
            .trimmingCharacters(in: .whitespaces), !name.isEmpty else { return nil }
        return name
    }

    /// Saves the Music Assistant user for a member. Empty removes it.
    func setMusicAssistantUser(_ name: String, for memberID: UUID) {
        guard var member = services.household.members.first(where: { $0.id == memberID }) else { return }
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        member.preferences[AudioSettings.musicAssistantUserPreference] = trimmed.isEmpty ? nil : .string(trimmed)
        services.household.update(member)
    }

    // MARK: SpotifyMemberAccounts

    public func spotifyAccount(for member: UUID) -> SpotifyMemberAccount {
        let owner = SpotifyAccountOwner.member(member)
        let isSetUp = spotify.isEnabled && !spotify.clientID.isEmpty
        return SpotifyMemberAccount(
            isSetUp: isSetUp,
            clientID: isSetUp ? spotify.clientID : nil,
            accountName: spotify.accounts.record(owner)?.user?.name,
            isSignedIn: spotify.accounts.signedIn.contains(owner),
            needsSignInAgain: spotify.accounts.needsSignInAgain(owner)
        )
    }

    public func linkSpotify(code: String, verifier: String, for member: UUID, from deviceName: String) async throws -> SpotifyMemberAccount {
        guard services.household.members.contains(where: { $0.id == member }) else {
            throw SpotifyError.signInFailed("That person isn't in this HomePad's household.")
        }
        guard spotify.isEnabled else { throw SpotifyError.notSetUp }
        try await spotify.adopt(code: code, verifier: verifier, for: .member(member), signedInOn: deviceName)
        return spotifyAccount(for: member)
    }

    public func signOutSpotify(for member: UUID) {
        spotify.signOut(.member(member))
    }
}

extension MusicPage {
    /// A page of a Spotify item, which belongs to the account that showed it.
    var isSpotify: Bool {
        if case .spotify = self { return true }
        return false
    }
}
