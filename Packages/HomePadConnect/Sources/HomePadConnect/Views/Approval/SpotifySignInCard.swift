import AuthenticationServices
import HomePadCore
import HomePadUI
import SwiftUI

/// On an iPhone, in a HomePad's remote, once the iPhone is linked to someone
/// there: their own Spotify on that HomePad. They sign in here, on their own
/// phone, and the HomePad keeps the sign-in for them only (`PhoneSpotifySignIn`).
struct SpotifySignInCard: View {
    @Environment(ConnectRuntime.self) private var connect
    @Environment(\.webAuthenticationSession) private var webAuthenticationSession
    let peer: PeerDevice
    /// True once the HomePad had time to answer, so an older one says to update.
    @State private var hasWaited = false

    private var spotify: PhoneSpotifySignIn { connect.spotifySignIn }
    private var member: ApprovalMember? { connect.approvals.states[peer.id]?.linkedMember }

    var body: some View {
        if connect.link.identity.kind == .iPhone, let member, connect.remote.status(of: peer.id) != nil {
            VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                SectionHeader("My Spotify", systemImage: "music.note")
                VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                    content(member)
                }
                .padding(Theme.Spacing.m)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
                if let error = spotify.errors[peer.id] {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .font(.footnote)
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .task(id: member.id) {
                await spotify.requestState(of: peer.id)
                try? await Task.sleep(for: .seconds(4))
                hasWaited = true
            }
        }
    }

    @ViewBuilder
    private func content(_ member: ApprovalMember) -> some View {
        if let state = spotify.states[peer.id] {
            if let account = state.account, account.isSetUp {
                if account.isSignedIn {
                    signedIn(account, member)
                } else {
                    signInOffer(account, member)
                }
            } else {
                Text("Spotify isn't set up on \(peer.name). Turn it on there in Settings, under Audio and AirPlay, Spotify.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } else if hasWaited {
            Text("Update HomePad on \(peer.name) to sign in to Spotify from here.")
                .foregroundStyle(.secondary)
        } else {
            ProgressView()
        }
    }

    @ViewBuilder
    private func signedIn(_ account: SpotifyMemberAccount, _ member: ApprovalMember) -> some View {
        LabeledContent("Signed In", value: account.accountName ?? "Your Account")
            .font(.headline)
        Text("While \(peer.name) recognizes \(member.name), Spotify there uses this account: your library, playlists, searches and Now Playing. It plays on \(peer.name) when the Spotify app there is signed in as you, and otherwise on your own phone, computer or speakers.")
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        Button("Sign Out on \(peer.name)", role: .destructive) {
            Task { await spotify.signOut(on: peer.id) }
        }
        .disabled(spotify.busy.contains(peer.id))
    }

    @ViewBuilder
    private func signInOffer(_ account: SpotifyMemberAccount, _ member: ApprovalMember) -> some View {
        Text(account.needsSignInAgain
             ? "Spotify ended your sign-in on \(peer.name), as it does every six months. Sign in again here."
             : "Use your own Spotify on \(peer.name) while it recognizes \(member.name). Sign in here, and \(peer.name) keeps the sign-in for you only. Your password stays on this iPhone.")
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        Button {
            signIn()
        } label: {
            if spotify.busy.contains(peer.id) {
                ProgressView().frame(maxWidth: .infinity)
            } else {
                Label(account.needsSignInAgain ? "Sign In Again" : "Sign In to Spotify", systemImage: "person.crop.circle.badge.checkmark")
                    .frame(maxWidth: .infinity)
            }
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .disabled(spotify.busy.contains(peer.id))
        Text("Your Spotify account must be on the household's Spotify app user list. Ask whoever set up Spotify on \(peer.name) to add it. Face ID confirms it is you before the sign-in is sent.")
            .font(.footnote)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func signIn() {
        Task {
            await spotify.signIn(on: peer.id, homePadName: peer.name) { url, scheme in
                // The person's own phone: a Spotify sign-in Safari already has is offered.
                try await webAuthenticationSession.authenticate(
                    using: url, callback: .customScheme(scheme), preferredBrowserSession: .shared,
                    additionalHeaderFields: [:]
                )
            }
        }
    }
}
