import AuthenticationServices
import HomePadCore
import HomePadUI
import SwiftUI
import UIKit

/// Settings > Audio & AirPlay > Spotify: turn Spotify on as a music source,
/// and open its setup, which shows where it stands.
struct SpotifySettingsSection: View {
    @Environment(AudioMediaService.self) private var media
    @Environment(AppServices.self) private var services

    var body: some View {
        let spotify = media.spotify
        Section {
            Toggle("Spotify as a Music Source", isOn: Binding(
                get: { spotify.isEnabled },
                set: { services.settings[AudioSettings.spotifyEnabled] = $0 }
            ))
            if spotify.isEnabled {
                NavigationLink {
                    SpotifySetupView().environment(media).environment(services)
                } label: {
                    LabeledContent("Spotify Setup", value: spotify.statusTitle)
                }
            }
        } header: {
            Text("Spotify")
        } footer: {
            Text(spotify.isEnabled
                 ? "The Spotify app on this iPad plays, and its sound follows this iPad's AirPlay, so it reaches your HomePods. HomePad browses, searches and controls it."
                 : "Plays Spotify through the Spotify app on this iPad, to the speakers you pick in AirPlay, and controls your Spotify Connect speakers. Needs Spotify Premium and the Spotify app.")
        }
    }
}

/// The steps that set Spotify up, in order.
enum SpotifySetupStep: Int, CaseIterable, Comparable {
    case createApp = 1, addAccounts, pasteClientID, signIn, openSpotify

    static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }

    var title: String {
        switch self {
        case .createApp: "Create a Spotify App"
        case .addAccounts: "Add Who Signs In"
        case .pasteClientID: "Paste the Client ID"
        case .signIn: "Sign In Each Person"
        case .openSpotify: "Play Once in Spotify Here"
        }
    }

    /// The first step not done, nil once Spotify plays on this iPad. HomePad
    /// cannot see the developer dashboard, so the first three count as done
    /// once a client ID works, and each problem Spotify reports points back
    /// to the step that fixes it.
    static func next(status: SpotifyService.Status, here: SpotifyService.HereState) -> SpotifySetupStep? {
        switch status {
        case .off, .needsClientID: return .createApp
        case .signedOut, .signingIn: return .signIn
        case .problem(.notAllowed): return .addAccounts
        case .problem(.invalidClientID), .problem(.notSetUp): return .pasteClientID
        case .problem: return .signIn
        case .ready: return here == .unknown ? .openSpotify : nil
        }
    }
}

/// Spotify's setup as a short guide: what to enter on Spotify's developer
/// dashboard, the client ID, the sign-in, and the first play in the Spotify
/// app here. Each step shows a check once it is done.
///
/// `-HomePadSpotifySetup YES` opens it from Settings > Audio & AirPlay, for
/// screenshots, and `-HomePadSpotifyAccounts YES` scrolls it to the accounts.
struct SpotifySetupView: View {
    @Environment(AudioMediaService.self) private var media
    @Environment(\.openURL) private var openURL
    @State private var clientID = ""

    /// What to type on the dashboard. The redirect URI must match exactly.
    static let appName = "HomePad"
    static let appDescription = "Spotify on my HomePad iPad"
    static let dashboardURL = URL(string: "https://developer.spotify.com/dashboard")!

    var body: some View {
        ScrollViewReader { proxy in
            form
                .task {
                    guard UserDefaults.standard.bool(forKey: "HomePadSpotifyAccounts") else { return }
                    // After the form has laid out its rows.
                    try? await Task.sleep(for: .milliseconds(500))
                    proxy.scrollTo(SpotifySetupStep.signIn, anchor: .top)
                }
        }
        .navigationTitle("Spotify")
        .spotifyNoticeAlert(media)
        .onAppear {
            clientID = media.spotify.clientID
            media.spotify.watch()
            Task { await media.refreshSpotify() }
        }
        .onDisappear { media.spotify.unwatch() }
    }

    private var form: some View {
        let spotify = media.spotify
        return Form {
            Section {
                LabeledContent("Status", value: spotify.statusTitle)
                LabeledContent("Account in Use", value: inUseText)
                if let problem = spotify.problem {
                    Text(problem.localizedDescription).font(.callout).foregroundStyle(.orange)
                }
            } footer: {
                Text("Once, about five minutes. Spotify asks for a developer app even for one person, and Premium for the account that makes it.")
            }
            Section {
                Text("Sign in at Spotify for Developers with your Premium account, choose Create App, and enter these. Under the APIs to use, check only Web API. Then save.")
                CopyableValueRow(label: "App Name", value: Self.appName)
                CopyableValueRow(label: "App Description", value: Self.appDescription)
                CopyableValueRow(label: "Redirect URI", value: SpotifyAuth.redirectURI)
                Button("Open Spotify for Developers", systemImage: "arrow.up.forward.app") { openURL(Self.dashboardURL) }
            } header: {
                header(.createApp)
            } footer: {
                Text("Leave Website, Bundle IDs and Android Packages empty. HomePad needs no client secret and no iOS SDK.")
            }
            Section {
                Text("In your new app, open User Management and add the name and email of each Spotify account that will sign in here: yours, each person's own, and the household's if it is another. Up to five.")
            } header: {
                header(.addAccounts)
            }
            Section {
                TextField("Client ID", text: $clientID)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .font(.body.monospaced())
                    .onSubmit { spotify.setClientID(clientID) }
                    .onChange(of: clientID) { _, new in
                        // A pasted ID is 32 characters. Save it without needing Return.
                        if new.trimmingCharacters(in: .whitespaces).count == 32 { spotify.setClientID(new) }
                    }
            } header: {
                header(.pasteClientID)
            } footer: {
                Text("Your app's Basic Information shows it. HomePad keeps it in the keychain.")
            }
            Section {
                SpotifyAccountRows()
            } header: {
                header(.signIn)
                    .id(SpotifySetupStep.signIn)
            } footer: {
                Text("While HomePad recognizes someone with their own account, Spotify in Music uses it: their library, playlists, searches and Now Playing. Guests, and people without one, use the household's. Music that plays keeps its account until it stops. Sign-ins stay on this iPad only. Spotify asks each person to sign in again every six months.")
            }
            Section {
                LabeledContent("Spotify on This iPad", value: hereText)
                if spotify.isReady, spotify.hereState != .open, SpotifyLinks.isInstalled, !UIAccessibility.isGuidedAccessEnabled {
                    Button("Open Spotify", systemImage: "arrow.up.forward.app") { media.wakeSpotifyHere() }
                }
            } header: {
                header(.openSpotify)
            } footer: {
                Text("Open Spotify on this iPad and play any song for a few seconds. HomePad then knows it, and pick your HomePods with the AirPlay button in Music. The Spotify app here plays only the music of the account it is signed in to, so people with other accounts play on their own phone, computer or speakers. Guided Access stops HomePad from opening Spotify, so open it before you start Guided Access.")
            }
        }
    }

    /// A step's number and title, with a check once it is done.
    private func header(_ step: SpotifySetupStep) -> some View {
        let next = SpotifySetupStep.next(status: media.spotify.status, here: media.spotify.hereState)
        let isDone = next.map { step < $0 } ?? true
        return HStack(spacing: Theme.Spacing.xs) {
            Text("\(step.rawValue). \(step.title)")
            if isDone {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green).accessibilityLabel("Done")
            }
        }
    }

    /// Whose account Spotify uses now.
    private var inUseText: String {
        switch media.spotify.owner {
        case nil: "None"
        case .household: "Household"
        case .member(let id): media.spotify.memberName(id) ?? "Someone"
        }
    }

    private var hereText: String {
        guard media.spotify.isReady else { return "After Sign In" }
        if !SpotifyLinks.isInstalled { return "Not Installed" }
        if let other = media.spotify.thisIPadIsOthers { return "Signed In as \(other)" }
        switch media.spotify.hereState {
        case .open: return media.spotifyVolume.speakerName.map { "Open, Playing to \($0)" } ?? "Open"
        case .notOpen: return "Not Open"
        case .unknown: return "Not Met Yet"
        }
    }
}

extension SpotifyService {
    /// One short line for where Spotify stands, for Settings.
    var statusTitle: String {
        switch status {
        case .off: return "Off"
        case .needsClientID: return "Needs Client ID"
        case .signedOut: return "Not Signed In"
        case .signingIn: return "Signing In"
        case .ready:
            if problem == .needsPremium { return "Needs Premium" }
            if problem == .noActiveDevice { return "No Device On" }
            if targetsThisIPad, hasReadDevices, hereState != .open { return "Spotify Not Open Here" }
            return accountName.map { "Signed In as \($0)" } ?? "Signed In"
        case .problem(let problem):
            switch problem {
            case .needsPremium: return "Needs Premium"
            case .notAllowed: return "Account Not on User List"
            case .invalidClientID: return "Unknown Client ID"
            default: return "Sign In Again"
            }
        }
    }
}
