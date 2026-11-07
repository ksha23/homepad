import HomePadCore
import HomePadUI
import SwiftUI

/// Music's full-screen player: big artwork, title and artist, scrubber,
/// transport, speakers and volume, for whatever plays in the house (this iPad
/// or a Music Assistant speaker). Music presents it full screen
/// (`media.isPlayerOpen`), as Apple Music on iPad does: the mini player, the Now
/// Playing pill and anything that opens "nowplaying" bring it up, and a drag
/// down or the chevron top right puts it away, back to Music as it was. It
/// steps aside for the assistant, the doorbell, a finished timer and an
/// intercom message, which the shell draws under any presentation.
///
/// The layout depends only on the space available (`NowPlayingLayout`), never on
/// what plays, so skipping tracks never moves anything. Artwork and text crossfade.
///
/// It stays dark in Light too, as Apple Music's player does, since its page is
/// a dark wash of the cover.
///
/// With Artwork Fills the Screen on (off by default), a few seconds after the
/// last touch the controls fade and the artwork fills the screen
/// (`NowPlayingPoster`), as HomeView's player does. A touch anywhere brings the
/// controls back without pressing what is under it.
struct NowPlayingView: View {
    @Environment(AudioMediaService.self) private var media
    @Environment(AppServices.self) private var services
    @Environment(\.accessibilityVoiceOverEnabled) private var isVoiceOverOn
    @State private var showsQueue = UserDefaults.standard.bool(forKey: "HomePadNowPlayingQueue")
    @State private var showsSpeakerPicker = false
    /// Counted up each time Play On closes, and part of its identity, so each opening is a new panel
    /// (see `swipeDownToDismiss`).
    @State private var speakerPickerClosings = 0
    @State private var showsAirPlay = false
    /// The controls have faded, leaving the artwork.
    @State private var isIdle = false
    /// Counts touches, so each one restarts the wait before the controls fade.
    @State private var touches = 0
    @State private var controlsOpacity: Double = 1.0

    /// How long the controls stay after the last touch.
    static let controlsFadeAfter: Duration = .seconds(6)

    var body: some View {
        let showsPoster = isIdle && fadesWhenIdle && media.nowPlaying != nil
        ZStack {
            // The controls stay in place while hidden, so the cover and the
            // scrubber are ready the moment they come back.
            controls
                .opacity(showsPoster ? 0 : 1)
                .allowsHitTesting(!showsPoster)
                .accessibilityHidden(showsPoster)
            if showsPoster, let nowPlaying = media.nowPlaying {
                NowPlayingPoster(nowPlaying: nowPlaying)
                    .transition(.opacity)
            }
        }
        .animation(.smooth(duration: 0.8), value: showsPoster)
        // A background, so the artwork wash never sizes the screen. As a stack layer,
        // a square cover filled to the screen's width made the screen as tall as it
        // was wide, which picked the portrait layout and cut off the top and bottom
        // (and jumped between layouts while each new cover loaded).
        .background { NowPlayingBackdrop(nowPlaying: media.nowPlaying) }
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
        // A presentation gets neither the shell's margin nor Music's night mode.
        .coverScreenMargin()
        // Nor the shell's home bar. Light on the player's dark page.
        .coverHomeBar()
        .nightModeAware()
        .task { await stepAsideForAlerts() }
        .onChange(of: services.assistant.phase) { _, phase in
            if phase != .idle { media.closePlayer() }
        }
        .task {
            // Fade in controls gracefully as the hero artwork completes its zoom expansion,
            // preventing heavy glass shaders from stalling frame 0 during the zoom.
            try? await Task.sleep(for: .milliseconds(100))
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.35)) {
                controlsOpacity = 1.0
            }
        }
        .task {
            // Wait for opening animation to settle before scanning AirPlay network routes
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            media.routes.beginDetection()
            media.spotify.watch()
        }
        .onDisappear {
            media.routes.endDetection()
            media.spotify.unwatch()
        }
        .sheet(isPresented: $showsQueue) { QueueSheet().environment(media) }
        .spotifyNoticeAlert(media)
        .background {
            if fadesWhenIdle { TouchObserver(onTouch: noteTouch) }
        }
        // Restarts with every touch. While the controls must stay (the setting
        // is off, nothing plays, a picker or Up Next is open, VoiceOver is on)
        // it waits for nothing, and starts over once they may fade again.
        .task(id: canFade ? touches : -1) {
            guard canFade else { return }
            try? await Task.sleep(for: Self.controlsFadeAfter)
            if !Task.isCancelled { isIdle = true }
        }
        .persistentSystemOverlays(.hidden)
        // Dark in every appearance, like Apple Music's player: its page is the
        // cover's dark wash, so its text, glass and Up Next stay light on dark.
        .environment(\.colorScheme, .dark)
        #if os(iOS)
        .gesture(DirectionalPan(.down, onChanged: { _ in }, onEnded: { translation, velocity in
            if translation.height > 40 || velocity.height > 200 {
                FPSMonitor.shared.start(name: "MusicPlayer.collapse", duration: 1.2)
                media.closePlayer()
            }
        }))
        #endif
    }

    private var fadesWhenIdle: Bool {
        services.settings[AudioSettings.nowPlayingFullScreenArtwork]
    }

    private var canFade: Bool {
        fadesWhenIdle && media.nowPlaying != nil && !showsSpeakerPicker && !showsQueue && !isVoiceOverOn
    }

    /// The shell draws its alerts under any presentation, so the player
    /// closes for them, back to Music.
    private func stepAsideForAlerts() async {
        for await event in services.events.stream() {
            switch event {
            case .doorbellRang, .timerFinished, .intercomReceived, .invokeAssistant:
                media.closePlayer()
            default:
                break
            }
        }
    }

    private func noteTouch() {
        isIdle = false
        touches &+= 1
    }

    private var controls: some View {
        VStack(spacing: 0) {
            AppHeader("Now Playing", accessory: { headerButtons })
                .padding([.horizontal, .top], Theme.Spacing.l)
                .opacity(controlsOpacity)
            GeometryReader { proxy in
                let size = settledSize(proxy.size)
                let layout = NowPlayingLayout(size: size, padding: Theme.Spacing.l)
                if let nowPlaying = media.nowPlaying {
                    content(nowPlaying, layout: layout)
                        .frame(width: size.width, height: size.height)
                } else {
                    emptyState.frame(width: size.width, height: size.height)
                }
            }
        }
    }

    private func settledSize(_ current: CGSize) -> CGSize {
        #if os(iOS)
        let screen = (UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first?.screen.bounds.size)
            ?? UIScreen.main.bounds.size
        let isLandscape = current.width >= current.height || screen.width >= screen.height
        let screenWidth = isLandscape ? max(screen.width, screen.height) : min(screen.width, screen.height)
        let screenHeight = isLandscape ? min(screen.width, screen.height) : max(screen.width, screen.height)
        let targetHeight = max(100, screenHeight - 80)
        let targetWidth = screenWidth

        // During zoom transitions, current starts at mini-player dimensions (~640x56)
        // and expands to full screen. Using the target settled size prevents reflowing fonts,
        // reallocating image pipelines and thrashing layout on all 120 animation frames.
        if current.height < targetHeight * 0.75 || current.width < targetWidth * 0.75 {
            return CGSize(width: targetWidth, height: targetHeight)
        }
        #endif
        return current
    }

    @ViewBuilder
    private var headerButtons: some View {
        // While this iPad plays (Apple's player, radio, or the Spotify app here),
        // Apple's AirPlay picker, as in Music's header. Music Assistant speakers
        // and other Spotify devices are not AirPlay, so they get the panel.
        let playsHere = media.nowPlayingUsesAirPlay
        GlassCapsuleButton(media.currentRouteName, systemImage: playsHere ? "airplayaudio" : "hifispeaker.2.fill") {
            if playsHere { showsAirPlay = true } else { showsSpeakerPicker = true }
        }
        .airPlayPicker(isPresented: $showsAirPlay)
        .accessibilityLabel("Playing on \(media.currentRouteName). Choose speakers")
        GlassIconButton("list.bullet", label: "Up Next") { showsQueue = true }
            .disabled(media.nowPlaying == nil)
        if media.focus == .local {
            // Stops what this iPad plays, as Sleep Sounds' timer does.
            HeaderMenu("Sleep Timer", systemImage: media.sleepTimer.isActive ? "moon.zzz.fill" : "moon.zzz") {
                ForEach(SleepTimer.choices, id: \.self) { minutes in
                    Button(minutes == 0 ? "Off" : "Stop in \(SleepTimer.label(minutes: minutes))") {
                        if minutes == 0 { media.sleepTimer.cancel() } else { media.sleepTimer.start(minutes: minutes) }
                    }
                }
            }
            .toolbarItemPriority(.low)
        }
        // Leaving is top right. The app's own close button, when shown, closes Music.
        GlassIconButton("chevron.down", label: "Close Player") {
            #if os(iOS)
            FPSMonitor.shared.start(name: "MusicPlayer.collapse", duration: 1.2)
            #endif
            withAnimation(.easeIn(duration: 0.15)) {
                controlsOpacity = 0.0
            }
            media.closePlayer()
        }
    }

    @ViewBuilder
    private func content(_ nowPlaying: NowPlaying, layout: NowPlayingLayout) -> some View {
        let stack = layout.isLandscape
            ? AnyLayout(HStackLayout(alignment: .center, spacing: layout.gap))
            : AnyLayout(VStackLayout(alignment: .center, spacing: layout.gap))
        stack {
            NowPlayingArtwork(nowPlaying: nowPlaying, cornerRadius: Theme.Radius.tile, prefetchesNext: true)
                .frame(width: layout.artworkSide, height: layout.artworkSide)
                .background {
                    // The shadow comes from a fixed card, not the cover. From the
                    // cover it faded and came back as covers crossfaded or loaded.
                    RoundedRectangle(cornerRadius: Theme.Radius.tile, style: .continuous)
                        .fill(.black)
                        .shadow(color: .black.opacity(0.4), radius: 16, y: 8)
                }
            NowPlayingDetails(nowPlaying: nowPlaying, titleSize: layout.titleSize)
                .frame(width: layout.detailsWidth, height: layout.detailsHeight)
                .opacity(controlsOpacity)
        }
        .padding(layout.padding)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyState: some View {
        VStack(spacing: Theme.Spacing.l) {
            EmptyStateView(
                "Nothing Playing",
                message: "Play something from Music, then choose where it plays.",
                systemImage: "music.note",
                actionTitle: "Browse Music"
            ) {
                services.events.post(.openApp(id: AudioModule.musicAppID))
            }
            ElsewhereInTheHouseStrip()
        }
        .opacity(controlsOpacity)
    }
}

/// Sizes for Now Playing, derived only from the space below the header, so the
/// artwork and controls always fit and never change while tracks change.
struct NowPlayingLayout: Equatable {
    let isLandscape: Bool
    let artworkSide: CGFloat
    let detailsWidth: CGFloat
    let detailsHeight: CGFloat
    let titleSize: CGFloat
    let gap: CGFloat
    let padding: CGFloat

    /// The details column needs about this much height: title, artist, scrubber, transport and volume.
    static let detailsMinHeight: CGFloat = 500

    init(size: CGSize, padding: CGFloat) {
        let width = max(0, size.width - padding * 2)
        let height = max(0, size.height - padding * 2)
        self.padding = padding
        gap = Theme.Spacing.xl
        isLandscape = size.width > size.height * 1.1
        if isLandscape {
            artworkSide = max(0, min(height, width * 0.5))
            detailsWidth = max(0, width - artworkSide - gap)
            detailsHeight = height
        } else {
            artworkSide = max(0, min(width * 0.86, height - Self.detailsMinHeight - gap))
            detailsWidth = width
            detailsHeight = max(0, height - artworkSide - gap)
        }
        // Readable from across the room: about 48 points on the 11-inch iPad,
        // at least as tall on the glass as Apple's title on HomeView's 7-inch screen.
        titleSize = min(64, max(40, min(detailsHeight * 0.1, detailsWidth * 0.09)))
    }
}

/// A soft, blurred wash of the artwork behind Now Playing, kept dark for the
/// always-on screen. The previous wash stays until the next one is ready and
/// then crossfades, so a skip never flashes black or pops in late.
private struct NowPlayingBackdrop: View {
    var nowPlaying: NowPlaying?
    @State private var wash: Wash?

    init(nowPlaying: NowPlaying?) {
        self.nowPlaying = nowPlaying
        // A cover washed before shows from the first frame. Each opening of the
        // player is a new view, which started black and faded the wash in late.
        if let url = ArtworkWash.webURL(for: nowPlaying?.artworkURL), let image = ArtworkWash.cachedImage(for: url) {
            _wash = State(initialValue: Wash(url: url, image: image))
        }
    }

    private struct Wash: Equatable {
        let url: URL
        let image: UIImage
    }

    /// The cover's web image. Generated covers have none and get a gradient.
    private var url: URL? {
        ArtworkWash.webURL(for: nowPlaying?.artworkURL)
    }

    var body: some View {
        let url = url
        ZStack {
            Color.black
            if url != nil, let wash {
                Color.clear
                    .overlay {
                        Image(uiImage: wash.image)
                            .resizable()
                            .interpolation(.low)
                            .scaledToFill()
                    }
                    .clipped()
                    .opacity(0.55)
                    .id(wash.url)
                    .transition(.opacity)
            } else if url == nil {
                let colors = GeneratedArtwork.colors(for: nowPlaying?.album ?? nowPlaying?.title ?? "Music")
                LinearGradient(colors: [colors.0.opacity(0.35), colors.1.opacity(0.25), .black],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
                    .transition(.opacity)
            }
            LinearGradient(colors: [.clear, .black.opacity(0.6)], startPoint: .top, endPoint: .bottom)
        }
        .animation(.smooth(duration: 0.8), value: wash?.url)
        .animation(.smooth(duration: 0.8), value: url == nil ? nowPlaying?.album ?? nowPlaying?.title : nil)
        .task(id: url) {
            guard let url, wash?.url != url else { return }
            guard let image = await ArtworkWash.image(for: url), !Task.isCancelled else { return }
            wash = Wash(url: url, image: image)
        }
        .ignoresSafeArea()
    }
}
