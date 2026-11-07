import AuthenticationServices
import HomePadCore
import HomePadUI
import SwiftUI

/// Spotify Setup's accounts: the household's, for guests and anyone without
/// their own, then each member's. A member signs in on their own iPhone, or
/// here while HomePad recognizes them, so nobody signs in as someone else.
struct SpotifyAccountRows: View {
    @Environment(AudioMediaService.self) private var media
    @Environment(AppServices.self) private var services
    @Environment(\.webAuthenticationSession) private var webAuthenticationSession

    var body: some View {
        accountRow(.household, title: "Household")
        ForEach(services.household.members) { member in
            accountRow(.member(member.id), title: member.name)
        }
    }

    private func accountRow(_ owner: SpotifyAccountOwner, title: String) -> some View {
        let spotify = media.spotify
        let record = spotify.accounts.record(owner)
        return VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            LabeledContent(title, value: state(owner, record))
            Text(detail(owner, record, title: title))
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: Theme.Spacing.l) {
                // A signed-in account offers only Sign Out. Another account goes in after it.
                if canSignInHere(owner), spotify.signingIn != owner, !spotify.accounts.signedIn.contains(owner) {
                    Button(record == nil ? "Sign In Here" : "Sign In Again Here") { signIn(owner) }
                        .disabled(spotify.clientID.isEmpty || spotify.signingIn != nil)
                }
                if record != nil {
                    Button("Sign Out", role: .destructive) { spotify.signOut(owner) }
                }
            }
            .buttonStyle(.borderless)
        }
        .padding(.vertical, Theme.Spacing.xs / 2)
    }

    private func state(_ owner: SpotifyAccountOwner, _ record: SpotifyAccountRecord?) -> String {
        let accounts = media.spotify.accounts
        if media.spotify.signingIn == owner { return "Signing In" }
        guard let record else { return "Not Signed In" }
        if accounts.needsSignInAgain(owner) { return "Sign In Again" }
        return record.user?.name ?? "Signed In"
    }

    private func detail(_ owner: SpotifyAccountOwner, _ record: SpotifyAccountRecord?, title: String) -> String {
        let inUse = media.spotify.owner == owner ? "In use now. " : ""
        if let record {
            let place = record.signedInOn.map { "Signed in on \($0)" } ?? "Signed in on this iPad"
            let ended = media.spotify.accounts.needsSignInAgain(owner) ? " Spotify has ended it since." : ""
            return "\(inUse)\(place), \(record.signedInAt.formatted(date: .abbreviated, time: .omitted)).\(ended)"
        }
        switch owner {
        case .household:
            return "For guests, and for anyone without their own account."
        case .member:
            return "\(title) signs in on their own iPhone: in HomePad, open this HomePad and choose Sign In to Spotify. Or here, while this HomePad recognizes \(title)."
        }
    }

    /// The household's account signs in here at any time. A member's only while
    /// HomePad recognizes that member, so nobody links someone else's.
    private func canSignInHere(_ owner: SpotifyAccountOwner) -> Bool {
        switch owner {
        case .household: true
        case .member(let id): services.household.unlockedMember?.id == id
        }
    }

    private func signIn(_ owner: SpotifyAccountOwner) {
        Task {
            await media.spotify.signIn(for: owner) { url, scheme in
                // Ephemeral, so no Spotify cookie stays in the browser of a shared iPad.
                try await webAuthenticationSession.authenticate(
                    using: url, callback: .customScheme(scheme), preferredBrowserSession: .ephemeral,
                    additionalHeaderFields: [:]
                )
            }
            await media.refreshSpotify()
        }
    }
}

/// Settings > Audio & AirPlay > Music Assistant Users: the Music Assistant user
/// each member's requests go to, so Music Assistant plays from their own
/// Spotify account and library. Shown once Music Assistant is ready.
struct MusicAssistantUsersSection: View {
    @Environment(AudioMediaService.self) private var media
    @Environment(AppServices.self) private var services

    var body: some View {
        if media.musicAssistant.isReady, !services.household.members.isEmpty {
            Section {
                ForEach(services.household.members) { member in
                    MusicAssistantUserField(member: member)
                }
            } header: {
                Text("Music Assistant Users")
            } footer: {
                Text("While HomePad recognizes someone, Music Assistant searches, shows the library and plays as their Music Assistant user, with the music sources that user may use, such as their own Spotify account. Add the users and their sources in Music Assistant, under Settings, User Management. Needs Home Assistant 2026.8 or later. Leave empty to use HomePad's Home Assistant user.")
            }
        }
    }
}

/// One member's Music Assistant user. Saved on Return or when Settings
/// closes, not on every letter, since a new user reloads what Music shows.
private struct MusicAssistantUserField: View {
    @Environment(AudioMediaService.self) private var media
    let member: HouseholdMember
    @State private var name = ""

    var body: some View {
        LabeledContent(member.name) {
            TextField("Music Assistant user", text: $name)
                .multilineTextAlignment(.trailing)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.done)
                .onSubmit(save)
        }
        .onAppear { name = AudioMediaService.musicAssistantUser(of: member) ?? "" }
        .onDisappear(perform: save)
    }

    private func save() {
        guard name.trimmingCharacters(in: .whitespaces) != (AudioMediaService.musicAssistantUser(of: member) ?? "") else { return }
        media.setMusicAssistantUser(name, for: member.id)
    }
}
