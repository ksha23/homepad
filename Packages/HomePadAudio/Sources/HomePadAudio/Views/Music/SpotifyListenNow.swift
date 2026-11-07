import HomePadCore
import HomePadUI
import SwiftUI
import UIKit

/// Listen Now with Spotify as the source: the setup state until Spotify is
/// ready, then whether the Spotify app here is open, shelves, Liked Songs, and
/// a link back to Spotify.
struct SpotifyListenNow: View {
    let shelves: [MusicShelfModel]
    @Environment(AudioMediaService.self) private var media

    var body: some View {
        let spotify = media.spotify
        if spotify.status != .ready {
            SpotifyStatusNote()
        } else if spotify.home.isEmpty && spotify.isLoadingHome {
            LoadingShelves(count: 3)
        } else {
            if spotify.targetsThisIPad, spotify.hasReadDevices, spotify.hereState != .open {
                SpotifyHereBanner()
            }
            if let kept = spotify.keptForPlayingMusic {
                GlassBanner(systemImage: "person.2.fill", tint: .green, title: "Playing From \(kept.prefix(1).uppercased() + kept.dropFirst()) Spotify",
                            subtitle: "Music shows this account until its music stops, so it can be paused here. Play something to switch to yours.")
            }
            if case .thisIPadIsOthers(let name) = spotify.target, spotify.hasReadDevices {
                let notice = SpotifyWake.signedInAsOther(name)
                GlassBanner(systemImage: "ipad.landscape", tint: .green, title: notice.title, subtitle: notice.message)
            }
            if let problem = spotify.problem {
                GlassBanner(systemImage: "exclamationmark.triangle.fill", tint: .orange, title: "Spotify", subtitle: problem.localizedDescription)
            }
            ForEach(shelves) { MusicShelf(shelf: $0) }
            SongGrid(title: "Liked Songs", items: spotify.home.likedSongs.map { SpotifyPages.tile($0, media, opensPage: false) })
            SpotifyAttribution()
        }
    }
}

/// What Spotify needs before it works, with the one action that moves it on.
struct SpotifyStatusNote: View {
    @Environment(AudioMediaService.self) private var media
    @Environment(AppServices.self) private var services

    var body: some View {
        GlassBanner(systemImage: "dot.radiowaves.up.forward", tint: .green, title: title, subtitle: message) {
            EmptyView()
        } actions: {
            GlassCapsuleButton("Open Settings", size: .regular, isProminent: true) {
                // The shell's own route to Settings > Audio & AirPlay, without asking iPadOS to open a link.
                services.events.post(.custom(name: ConnectEventName.openURL, payload: .string("homepad://settings/audio")))
            }
        }
    }

    private var title: String {
        switch media.spotify.status {
        case .needsClientID: "Set Up Spotify"
        case .signedOut, .signingIn: "Sign In to Spotify"
        case .problem(let problem) where problem.needsSignIn: "Sign In to Spotify Again"
        default: "Spotify"
        }
    }

    private var message: String {
        switch media.spotify.status {
        case .needsClientID:
            "Add your Spotify client ID in Settings, under Audio and AirPlay. The steps are there."
        case .signedOut, .signingIn:
            "Sign in once in Settings, under Audio and AirPlay. The Spotify app on this iPad then plays to your AirPlay speakers, and HomePad browses and controls it."
        case .problem(let problem) where problem.needsSignIn && media.spotify.owner?.memberID != nil:
            "Spotify ended your sign-in. Sign in again from HomePad on your iPhone, under My Spotify, or in Settings, under Audio and AirPlay, while HomePad recognizes you."
        case .problem(let problem):
            problem.localizedDescription
        default:
            "Spotify is off. Turn it on in Settings, under Audio and AirPlay."
        }
    }
}

/// The Spotify app on this iPad is not a Connect device right now: closed,
/// asleep after it stopped, or not yet met. Says what to do, with Open Spotify
/// when iPadOS allows HomePad to open it.
struct SpotifyHereBanner: View {
    @Environment(AudioMediaService.self) private var media
    @State private var isGuidedAccess = UIAccessibility.isGuidedAccessEnabled

    var body: some View {
        let advice = SpotifyWake.advice(isInstalled: SpotifyLinks.isInstalled, isGuidedAccess: isGuidedAccess)
        GlassBanner(systemImage: "ipad.landscape", tint: .green, title: title, subtitle: message(advice)) {
            EmptyView()
        } actions: {
            if advice == .openSpotify {
                GlassCapsuleButton("Open Spotify", systemImage: "arrow.up.forward.app", size: .regular, isProminent: true) {
                    media.wakeSpotifyHere()
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIAccessibility.guidedAccessStatusDidChangeNotification)) { _ in
            isGuidedAccess = UIAccessibility.isGuidedAccessEnabled
        }
    }

    private var title: String {
        media.spotify.hereState == .unknown ? "Play Once in Spotify" : "Spotify Isn't Open on This iPad"
    }

    private func message(_ advice: SpotifyWake) -> String {
        switch advice {
        case .openSpotify:
            media.spotify.hereState == .unknown
                ? "Open Spotify on this iPad and play any song for a few seconds, so HomePad learns which Spotify device this iPad is."
                : "Spotify plays here through the Spotify app. Play anything and HomePad opens it, or open it now."
        case .leaveGuidedAccess, .installSpotify, .notIdentified, .signedInAsOther:
            advice.message
        }
    }
}

extension View {
    /// Shows why Spotify could not play on this iPad, and what to do
    /// (`media.spotifyNotice`). On every screen that can start Spotify here.
    func spotifyNoticeAlert(_ media: AudioMediaService) -> some View {
        alert(media.spotifyNotice?.title ?? "Spotify", isPresented: Binding(
            get: { media.spotifyNotice != nil }, set: { if !$0 { media.spotifyNotice = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(media.spotifyNotice?.message ?? "")
        }
    }
}

/// Spotify asks apps that show its content to say so and link back to it.
struct SpotifyAttribution: View {
    var body: some View {
        HStack(spacing: Theme.Spacing.m) {
            Text("Music, artwork and playback from Spotify.")
                .font(.footnote)
                .foregroundStyle(.secondary)
            GlassCapsuleButton("Open Spotify", systemImage: "arrow.up.forward.app", size: .regular) {
                SpotifyLinks.openApp()
            }
        }
    }
}
