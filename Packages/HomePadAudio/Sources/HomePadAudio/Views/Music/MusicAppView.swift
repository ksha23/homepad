import HomePadCore
import HomePadUI
import SwiftUI

/// The "music" app. A sidebar on wide screens (chips on narrow ones) with Listen
/// Now, Search, Library and Speakers first, and the iPad-only Radio and Sleep
/// Sounds after. The header holds the music source as a menu next to the title
/// (when there is a choice) and the speaker button, which opens AirPlay or the
/// Play On panel. Album, playlist and artist pages push in the content column,
/// with a back button before their title, as in the Music app. It opens where
/// it was left (`MusicPlace`): the section, the Library's kind and the page.
/// It presents its full-screen player (`NowPlayingView`) while `media.isPlayerOpen`,
/// as Apple Music on iPad does: a full-screen presentation that zooms out of
/// the mini player and back into it, dragged down or put away with its chevron.
///
/// Launch arguments: `-HomePadMusicSection listenNow|search|library|speakers|radio|sleep`,
/// `-HomePadMusicSearch <text>`, `-HomePadMusicSpeakerPicker YES`,
/// `-HomePadMusicLibrary playlists|albums|artists|songs` and, with the demo,
/// `-HomePadMusicPage <album, playlist or artist name>`.
struct MusicAppView: View {
    @Environment(AudioMediaService.self) private var media
    @State private var showsSpeakerPicker = UserDefaults.standard.bool(forKey: "HomePadMusicSpeakerPicker")
    /// Counted up each time Play On closes, and part of its identity, so each opening is a new panel
    /// (see `swipeDownToDismiss`).
    @State private var speakerPickerClosings = 0
    @State private var showsAirPlay = false
    @State private var showsMusicAssistantPanel = false
    @Namespace private var playerZoom

    var body: some View {
        let page = media.pages.top
        AppScreen(page?.title ?? "Music", onBack: page.map { _ in { media.pages.pop() } },
                  backLabel: backLabel, accessory: { speakerButton }, titleAccessory: { if page == nil { sourcePicker } }) {
            GeometryReader { proxy in
                let isWide = proxy.size.width >= 900
                HStack(alignment: .top, spacing: Theme.Spacing.l) {
                    if isWide {
                        MusicSidebar(selection: sectionBinding) { showsMusicAssistantPanel = true }
                            .frame(width: 260)
                            .padding(.bottom, Theme.Spacing.l)
                    }
                    VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                        if !isWide, page == nil {
                            ChoiceChips(MusicSection.allCases.map { .init(id: $0, title: $0.title, systemImage: $0.systemImage) },
                                        selection: sectionBinding)
                        }
                        Group {
                            if let page {
                                MusicDetailView(page: page).id(page.id)
                            } else {
                                sectionContent
                            }
                        }
                        .environment(\.musicContentWidth, isWide ? proxy.size.width - 260 - Theme.Spacing.l : proxy.size.width)
                    }
                    .frame(maxHeight: .infinity, alignment: .top)
                    // Every section and page scrolls under the mini player, and
                    // the inset keeps its last row clear of it.
                    .safeAreaInset(edge: .bottom, spacing: 0) { MusicMiniPlayer(zoom: playerZoom) }
                }
            }
            // The content column runs down to the screen's margin, so pages
            // scroll under the floating mini player as in Apple Music.
            // AppScreen pads its content on every side, and this gives the
            // bottom padding back.
            .padding(.bottom, -Theme.Spacing.l)
        }
        .background(Color.screenBackground.ignoresSafeArea())
        .overlay {
            if showsSpeakerPicker {
                SpeakerPickerPanel {
                    showsSpeakerPicker = false
                    speakerPickerClosings += 1
                }
                .id(speakerPickerClosings)
                .transition(.opacity)
            }
        }
        .animation(Theme.Motion.settle, value: showsSpeakerPicker)
        .animation(Theme.Motion.standard, value: page?.id)
        // A real presentation, so iPadOS owns opening, closing and the drag down,
        // and its own menus (AirPlay) open over the player. Drawn as an overlay
        // inside Music, the player covered them. It draws the home bar itself
        // (`coverHomeBar()`), so a swipe up goes Home from it as from Music.
        .fullScreenCover(isPresented: Binding(get: { media.isPlayerOpen }, set: { if !$0 { media.closePlayer() } })) {
            NowPlayingView()
                .environment(media)
        }
        .fullScreenCover(isPresented: $showsMusicAssistantPanel) {
            MusicAssistantPanel { showsMusicAssistantPanel = false }
                .coverScreenMargin()
                .coverHomeBar()
        }
        // Why Spotify could not play on this iPad, and what to do (`SpotifyWake`).
        .spotifyNoticeAlert(media)
        .nightModeAware()
        .task { await media.refreshMusicSources() }
        .onAppear {
            media.reopenMusicPage()
            media.spotify.watch()
        }
        .onDisappear { media.spotify.unwatch() }
    }

    private var section: MusicSection { media.musicPlace.section }

    /// Choosing a section leaves any page that was open.
    private var sectionBinding: Binding<MusicSection> {
        Binding(get: { section }, set: { new in
            media.pages.popToRoot()
            media.musicPlace.section = new
        })
    }

    private var backLabel: String {
        media.pages.pages.count > 1 ? media.pages.pages[media.pages.pages.count - 2].title : section.title
    }

    /// This iPad, Music Assistant or Spotify, as a menu next to the title.
    @ViewBuilder
    private var sourcePicker: some View {
        if media.canChooseMusicSource {
            HeaderPicker("Music Source", selection: Binding(get: { media.musicSource }, set: { media.setMusicSource($0) }),
                         title: media.musicSource.title, systemImage: media.musicSource.systemImage) {
                ForEach(media.availableMusicSources) { Label($0.title, systemImage: $0.systemImage).tag($0) }
            }
        }
    }

    /// Where music plays, as a toolbar item that shrinks to its symbol when the
    /// header is short of room. When new music comes out of this iPad (Apple
    /// Music, or the Spotify app here) it opens Apple's AirPlay picker at once.
    /// Music Assistant's speakers and other Spotify devices are not AirPlay,
    /// so they get the panel.
    private var speakerButton: some View {
        GlassCapsuleButton(media.playbackDestinationName, systemImage: destinationSymbol) {
            if media.newMusicUsesAirPlay { showsAirPlay = true } else { showsSpeakerPicker = true }
        }
        .airPlayPicker(isPresented: $showsAirPlay)
        .accessibilityLabel("Playing on \(media.playbackDestinationName). Choose speakers")
    }

    private var destinationSymbol: String {
        if media.newMusicUsesAirPlay { return "airplayaudio" }
        switch media.musicSource {
        case .musicAssistant: return media.musicAssistant.targetPlayer?.model.systemImage ?? "hifispeaker.fill"
        case .spotify: return media.spotify.targetDevice?.systemImage ?? "hifispeaker.fill"
        case .thisIPad: return "airplayaudio"
        }
    }

    @ViewBuilder
    private var sectionContent: some View {
        switch section {
        case .listenNow: ListenNowView()
        case .search: MusicSearchView()
        case .library: LibraryView()
        case .speakers: SpeakersView(openPicker: { showsSpeakerPicker = true }, openMusicAssistant: { showsMusicAssistantPanel = true })
        case .radio: ScrollView { RadioSection().padding(.vertical, Theme.Spacing.m) }
        case .sleep: ScrollView { SleepSection().padding(.vertical, Theme.Spacing.m) }
        }
    }
}

/// The Music app's sections. Radio and Sleep Sounds always play on this iPad.
enum MusicSection: String, CaseIterable, Identifiable {
    case listenNow, search, library, speakers, radio, sleep
    var id: String { rawValue }

    var title: String {
        switch self {
        case .listenNow: "Listen Now"
        case .search: "Search"
        case .library: "Library"
        case .speakers: "Speakers"
        case .radio: "Radio"
        case .sleep: "Sleep Sounds"
        }
    }

    var systemImage: String {
        switch self {
        case .listenNow: "play.circle.fill"
        case .search: "magnifyingglass"
        case .library: "music.note.square.stack.fill"
        case .speakers: "hifispeaker.2.fill"
        case .radio: "dot.radiowaves.left.and.right"
        case .sleep: "moon.zzz.fill"
        }
    }

    static var primary: [MusicSection] { [.listenNow, .search, .library, .speakers] }
    static var onThisIPad: [MusicSection] { [.radio, .sleep] }
}

/// `-HomePadMusicPage <name>` opens a demo album, playlist or artist page, for screenshots.
@MainActor
enum MusicPageLaunch {
    /// Opens the page each time Music opens, over whatever was open. True when it did.
    @discardableResult
    static func open(in media: AudioMediaService) -> Bool {
        guard media.demo != nil, let name = UserDefaults.standard.string(forKey: "HomePadMusicPage") else { return false }
        let items = [MAMediaItem.MediaType.album, .playlist, .artist].flatMap(DemoMusicCatalog.items(of:))
        guard let item = items.first(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) else { return false }
        media.pages.popToRoot()
        media.pages.push(.demo(item))
        return true
    }
}

extension EnvironmentValues {
    /// The width the Music app's content column has, for laying out page headers and grids.
    @Entry var musicContentWidth: CGFloat = 1000
}
