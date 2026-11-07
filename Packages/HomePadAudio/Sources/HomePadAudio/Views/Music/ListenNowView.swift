import HomePadCore
import HomePadUI
import SwiftUI
import UIKit

/// Listen Now: shelves from the chosen source, led by Recently Played, which
/// starts with what the person using HomePad played here. What plays shows only
/// in the Music app's mini player, and speakers are chosen from the header's
/// AirPlay button or the Speakers section. Music Assistant shows its library.
/// This iPad shows Apple Music when the catalog works, the synced library when
/// it does not, and always radio picks, so the screen is never empty.
struct ListenNowView: View {
    @Environment(AudioMediaService.self) private var media
    /// Set after `patience`, so a slow source never holds the page back for long.
    @State private var waitedLongEnough = false

    /// How long the page waits for its data before showing what it has.
    private static let patience: Duration = .seconds(5)

    var body: some View {
        // One placeholder page until the source's data is in, then everything at
        // once. Drawn as it arrived, library shelves turned into Apple Music ones
        // and radio picks slid down.
        let isReady = waitedLongEnough || media.isListenNowReady
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
                if isReady {
                    let shelves = MusicShelves.current(media)
                    switch media.musicSource {
                    case .musicAssistant: musicAssistantShelves(shelves)
                    case .spotify: SpotifyListenNow(shelves: shelves)
                    case .thisIPad: thisIPadShelves(shelves)
                    }
                } else {
                    loadingPage
                }
            }
            .padding(.vertical, Theme.Spacing.s)
            .frame(maxWidth: .infinity, alignment: .leading)
            .animation(.smooth(duration: 0.35), value: isReady)
        }
        .scrollIndicators(.hidden)
        .task {
            try? await Task.sleep(for: Self.patience)
            waitedLongEnough = true
        }
    }

    /// Shelves of placeholders, so the page does not jump when it arrives.
    private var loadingPage: some View {
        LoadingShelves(count: 3)
            .transition(.opacity)
    }

    @ViewBuilder
    private func musicAssistantShelves(_ shelves: [MusicShelfModel]) -> some View {
        let assistant = media.musicAssistant
        if assistant.home.isEmpty && assistant.isLoadingHome {
            LoadingShelves(count: 3)
        } else if assistant.home.isEmpty {
            EmptyStateView("Nothing in Music Assistant Yet",
                           message: assistant.lastError ?? "Add music providers such as Apple Music or Spotify in Music Assistant, then come back.",
                           systemImage: "hifispeaker.2", actionTitle: "Try Again") {
                Task { await assistant.loadHome() }
            }
        } else {
            let playing = assistant.activePlayer
            ForEach(shelves) { MusicShelf(shelf: $0) }
            SongGrid(title: "Favorite Songs", items: assistant.home.favoriteTracks.prefix(8).map { MusicShelves.tile($0, media, playing: playing) })
        }
    }

    @ViewBuilder
    private func thisIPadShelves(_ shelves: [MusicShelfModel]) -> some View {
        if let library = media.memberMusic.shown {
            MemberMusicHeader(library: library, title: "\(library.memberName)'s Apple Music")
        }
        let status = media.catalog.status
        if media.demo == nil, status != .ready, status != .checking {
            AppleMusicStatusNote(status: status)
        }
        ForEach(shelves) { MusicShelf(shelf: $0) }
        MusicShelf(shelf: MusicShelves.radioPicks(media))
    }
}

/// A short, friendly note about Apple Music's status, with the fix and one action.
struct AppleMusicStatusNote: View {
    let status: AppleMusicStatus
    @Environment(AudioMediaService.self) private var media
    @Environment(\.openURL) private var openURL

    var body: some View {
        GlassBanner(systemImage: status.systemImage, tint: .pink, title: headline, subtitle: status.message) {
            EmptyView()
        } actions: {
            if let action {
                GlassCapsuleButton(action.title, size: .regular, isProminent: true) { action.run() }
            }
        }
    }

    private var headline: String {
        switch status {
        case .notAuthorized(let canAsk): canAsk ? "Connect Apple Music" : "Apple Music Is Off"
        default: "Apple Music: \(status.title)"
        }
    }

    private var action: (title: String, run: () -> Void)? {
        switch status {
        case .notAuthorized(true):
            ("Connect", { Task { await media.connectAppleMusic() } })
        case .notAuthorized(false):
            ("Open Settings", { if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) } })
        case .offline, .serviceNotEnabled:
            ("Try Again", { Task { await media.catalog.refreshStatus(force: true) } })
        default:
            nil
        }
    }
}

extension AudioMediaService {
    /// Asks for Media and Apple Music access, then loads whatever now works.
    func connectAppleMusic() async {
        _ = await appleMusic.requestAuthorization()
        await catalog.refreshStatus(force: true)
        if catalog.status.canBrowseCatalog { await catalog.loadHome() }
        mediaLibrary.load(force: true)
    }
}
