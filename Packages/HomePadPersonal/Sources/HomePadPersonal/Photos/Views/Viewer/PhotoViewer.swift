import HomePadCore
import HomePadUI
import SwiftUI

/// Photos and videos full screen, over the grid they came from, as in the
/// Photos app. It grows out of the tapped thumbnail. Swipe sideways for the
/// next or previous one, in grid order. Swipe down, or tap Close, and it
/// shrinks back into its thumbnail, with the grid scrolled to it. A video plays
/// only while it is the one on screen.
///
/// As a slideshow it moves on by itself, with slow crossfades and a gentle
/// zoom, and waits for each video to end. A tap shows its close button.
///
/// A drag locks to the axis it starts along (`DirectionalPan`), so paging
/// and swiping down never fight, and a drag on a video's own controls does
/// neither.
///
/// Every move is the photo's own rectangle changing, in the viewer's
/// coordinates: growing out of its thumbnail, following the finger down, and
/// landing on the thumbnail in one spring that carries the finger's speed. The
/// pages never scale or move as a whole. A scaled view loses the safe area it
/// ignores, which here is the shell's screen margin, so the viewer's space would
/// shift under the photo while it lands (`PhotoViewerGeometry`).
struct PhotoViewer: View {
    let request: PhotoViewerRequest
    /// Where a photo's thumbnail sits in the grid, in global coordinates, if it is on screen.
    let thumbnailFrame: (PhotoRef) -> CGRect?
    /// Told whenever another photo comes on, so the grid keeps it in view.
    let onShow: (PhotoRef) -> Void
    /// Removes the viewer once it has gone.
    let onClose: () -> Void

    @Environment(PhotoLibraryService.self) private var library
    @Environment(SettingsStore.self) private var settings
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private enum Phase { case opening, open, closing }

    @State private var phase = Phase.opening
    /// The page on screen, fractional mid-swipe (see `PhotoPaging`).
    @State private var position: CGFloat = 0
    /// The page a sideways drag started on, while one is under way.
    @State private var dragStart: Int?
    /// How far a swipe down has pulled the photo, across and down.
    @State private var pull: CGSize = .zero
    /// The viewer's own space, which covers the screen, in global coordinates.
    /// Measured inside the pages, where they are drawn: outside them it is only
    /// the safe area, inset by the shell's screen margin.
    @State private var area: CGRect = .zero
    /// The thumbnail the viewer grew out of, in global coordinates, so it opens from there.
    @State private var openingThumbnail: CGRect?
    /// Where the photo goes as the viewer closes, measured once as it starts.
    @State private var landing: PhotoLanding?
    @State private var showsControls = false
    /// The page a slideshow is fading out, drawn over the next one.
    @State private var fadingPage: Int?
    @State private var fadeOpacity = 1.0
    @State private var isZoomed = false

    init(request: PhotoViewerRequest, thumbnailFrame: @escaping (PhotoRef) -> CGRect?,
         onShow: @escaping (PhotoRef) -> Void, onClose: @escaping () -> Void) {
        self.request = request
        self.thumbnailFrame = thumbnailFrame
        self.onShow = onShow
        self.onClose = onClose
        // Set before the first frame, so the photo starts on its thumbnail and grows from there.
        _position = State(initialValue: CGFloat(request.startIndex))
        if request.mode == .browse, request.photos.indices.contains(request.startIndex) {
            _openingThumbnail = State(initialValue: thumbnailFrame(request.photos[request.startIndex]))
        }
    }

    private var policy: SwipeDismissPolicy { .standard }
    private var photos: [PhotoRef] { request.photos }
    private var isSlideshow: Bool { request.mode == .slideshow }
    private var current: Int { min(max(0, Int(position.rounded())), max(0, photos.count - 1)) }

    var body: some View {
        ZStack {
            Color.black
                .opacity(backdropOpacity)
                .ignoresSafeArea()
            pages
            chrome
        }
        .gesture(DirectionalPan(.down, isEnabled: phase == .open && dragStart == nil, onChanged: { translation in
            pull = translation
        }, onEnded: releaseDown))
        .gesture(TapGesture().onEnded {
            withAnimation(Theme.Motion.standard) { showsControls.toggle() }
        }, including: isSlideshow ? .all : .subviews)
        .accessibilityAction(.escape) { close() }
        // Dark in Light too, like the Photos app's viewer: the photo on black,
        // with its title and close button in white.
        .environment(\.colorScheme, .dark)
        .nightModeAware()
        .onAppear(perform: appear)
        .onChange(of: current) { _, index in show(index) }
        .task(id: SlideshowStep(page: current, isRunning: isSlideshow && phase == .open && dragStart == nil && pull == .zero)) {
            await runSlideshowStep()
        }
    }

    // MARK: Pages

    private var pages: some View {
        GeometryReader { proxy in
            let space = proxy.frame(in: .global)
            ZStack(alignment: .topLeading) {
                ForEach(pagesToDraw, id: \.self) { index in
                    page(index, in: space)
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .onGeometryChange(for: CGRect.self, of: { $0.frame(in: .global) }) { area = $0 }
        }
        .ignoresSafeArea()
        // The whole screen pages, including the black beside an upright photo
        // on a landscape screen, which has nothing of its own to touch.
        .contentShape(Rectangle())
        .opacity(contentOpacity)
        .gesture(DirectionalPan(.horizontal, isEnabled: phase == .open && pull == .zero, onChanged: dragPage, onEnded: releasePage))
        .accessibilityElement(children: .contain)
        .accessibilityScrollAction { edge in
            switch edge {
            case .trailing: settle(on: current + 1)
            case .leading: settle(on: current - 1)
            default: break
            }
        }
    }

    /// The pages on screen and one more each side, loaded ahead, plus the one a slideshow is fading out.
    private var pagesToDraw: [Int] {
        guard !photos.isEmpty else { return [] }
        var indices = Array(PhotoPaging.window(around: position, count: photos.count))
        if let fadingPage, !indices.contains(fadingPage) { indices.append(fadingPage) }
        return indices
    }

    /// One page, laid out in `space`, the pages' frame in global coordinates.
    private func page(_ index: Int, in space: CGRect) -> some View {
        let isCurrent = index == current
        return PhotoViewerPage(
            photo: photos[index], mode: request.mode, photoRect: photoRect(for: index, in: space),
            cornerRadius: cornerRadius(for: index),
            isActive: isCurrent && phase == .open, showsVideo: phase == .open || !isCurrent,
            zoom: zoom(for: index), onVideoFinished: { if isSlideshow { advance() } }
        )
        .frame(width: space.width, height: space.height)
        .offset(x: index == fadingPage ? 0 : PhotoPaging.offset(of: index, at: position, pageWidth: space.width))
        .opacity(pageOpacity(index))
        .zIndex(index == fadingPage ? 1 : 0)
        .accessibilityHidden(!isCurrent)
    }

    /// Where a page's photo sits in the viewer's coordinates. At rest a browsed
    /// photo fits the screen and a slideshow's page fills it. The one on screen
    /// grows out of its thumbnail as the viewer opens, follows the finger while
    /// pulled down, and goes to its landing as the viewer closes.
    private func photoRect(for index: Int, in space: CGRect) -> CGRect {
        let rest = restingRect(for: index, in: space.size)
        guard index == current, !reduceMotion else { return rest }
        switch phase {
        case .opening:
            return openingThumbnail.map { $0.offsetBy(dx: -space.minX, dy: -space.minY) } ?? rest
        case .open:
            return PhotoViewerGeometry.pulled(rest, by: pull, policy: policy)
        case .closing:
            return landing?.rect ?? rest
        }
    }

    private func restingRect(for index: Int, in size: CGSize) -> CGRect {
        if isSlideshow { return CGRect(origin: .zero, size: size) }
        return PhotoPaging.fittedRect(aspectRatio: library.aspectRatio(for: photos[index]), in: size)
    }

    /// The thumbnail's corners while the photo grows out of it or lands on it.
    private func cornerRadius(for index: Int) -> CGFloat {
        guard index == current, !reduceMotion else { return 0 }
        switch phase {
        case .opening: return openingThumbnail == nil ? 0 : Theme.Radius.thumbnail
        case .open: return 0
        case .closing: return landing == nil || landing?.kind == .away ? 0 : Theme.Radius.thumbnail
        }
    }

    private func pageOpacity(_ index: Int) -> Double {
        if index == fadingPage { return fadeOpacity }
        // Neighbours stay out of sight while the photo is pulled down, opens or closes.
        if index != current, pull != .zero || phase != .open { return 0 }
        // Off to the nearest place on screen, for a thumbnail scrolled away.
        if index == current, phase == .closing, landing?.kind == .nearest { return 0 }
        return 1
    }

    private func zoom(for index: Int) -> CGFloat {
        guard isSlideshow, !reduceMotion else { return 1 }
        if index == fadingPage { return 1.04 }
        return index == current && isZoomed ? 1.04 : 1
    }

    // MARK: Look

    private var backdropOpacity: Double {
        guard phase == .open else { return 0 }
        return reduceMotion ? policy.reducedMotionOpacity(for: pull.height) : policy.backdropOpacity(for: pull.height)
    }

    /// Without a thumbnail to grow from, the viewer fades in. With Reduce
    /// Motion it fades both ways.
    private var contentOpacity: Double {
        switch phase {
        case .opening: return openingThumbnail == nil || reduceMotion ? 0 : 1
        case .open: return reduceMotion ? policy.reducedMotionOpacity(for: pull.height) : 1
        case .closing: return reduceMotion ? 0 : 1
        }
    }

    @ViewBuilder
    private var chrome: some View {
        let opacity = phase == .open ? max(0, 1 - 3 * Double(policy.progress(for: pull.height))) : 0
        if isSlideshow {
            if showsControls {
                CloseButton { close() }
                    .padding(Theme.Spacing.l)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                    .opacity(opacity)
                    .transition(.opacity)
            }
        } else {
            DetailHeader(request.title, subtitle: "\(current + 1) of \(photos.count)", onClose: { close() })
                .padding(Theme.Spacing.l)
                .frame(maxHeight: .infinity, alignment: .top)
                .opacity(opacity)
                .allowsHitTesting(phase == .open)
        }
    }

    // MARK: Opening and closing

    private func appear() {
        show(current)
        withAnimation(reduceMotion ? Theme.Motion.standard : Theme.Motion.settle) { phase = .open }
    }

    /// Closes, or springs back to rest, from where the finger let go and at its speed.
    private func releaseDown(translation: CGSize, velocity: CGSize) {
        if policy.shouldClose(translation: translation.height, velocity: velocity.height) {
            close(velocity: velocity)
        } else {
            let rest = restingRect(for: current, in: area.size)
            let from = PhotoViewerGeometry.pulled(rest, by: pull, policy: policy)
            let speed = PhotoViewerGeometry.springVelocity(velocity, from: from, to: rest)
            withAnimation(.interpolatingSpring(Theme.Motion.settleSpring, initialVelocity: speed)) {
                pull = .zero
            }
        }
    }

    /// Lands the photo on its thumbnail, measured now, in one spring from
    /// wherever it is, then removes the viewer as the thumbnail shows again in
    /// the same place. Without a thumbnail it slides away (`PhotoLanding`), and
    /// with Reduce Motion it fades.
    private func close(velocity: CGSize = .zero) {
        guard phase == .open else { return }
        guard !reduceMotion else {
            withAnimation(Theme.Motion.standard) { phase = .closing } completion: { onClose() }
            return
        }
        let screen = CGRect(origin: .zero, size: area.size)
        let from = photoRect(for: current, in: area)
        let thumbnail = isSlideshow ? nil : thumbnailFrame(photos[current]).map { $0.offsetBy(dx: -area.minX, dy: -area.minY) }
        let landing = PhotoViewerGeometry.landing(thumbnail: thumbnail, from: from, in: screen)
        if SwipeTrace.trace.isEnabled {
            let found = thumbnail.map { "\(Int($0.minX)),\(Int($0.minY)) \(Int($0.width))x\(Int($0.height))" } ?? "none"
            SwipeTrace.trace.log("photo close: thumbnail \(found), landing \(landing.kind), viewer \(Int(area.minX)),\(Int(area.minY)) "
                                 + "\(Int(area.width))x\(Int(area.height)), slideshow \(isSlideshow)")
        }
        let speed = PhotoViewerGeometry.springVelocity(velocity, from: from, to: landing.rect)
        // Removed only once the spring has fully settled, so the thumbnail
        // takes over exactly where the photo is.
        withAnimation(.interpolatingSpring(Theme.Motion.settleSpring, initialVelocity: speed), completionCriteria: .removed) {
            self.landing = landing
            phase = .closing
        } completion: {
            onClose()
        }
    }

    // MARK: Paging

    private func dragPage(_ translation: CGSize) {
        if dragStart == nil { dragStart = current }
        let target = PhotoPaging.position(from: dragStart ?? current, translation: translation.width,
                                          pageWidth: area.width, count: photos.count)
        // Follows the finger, and smoothly takes over a page still settling from a quick swipe.
        withAnimation(Theme.Motion.follow) { position = target }
    }

    private func releasePage(translation: CGSize, velocity: CGSize) {
        let start = dragStart ?? current
        dragStart = nil
        let target = PhotoPaging.target(from: start, translation: translation.width, velocity: velocity.width,
                                        pageWidth: area.width, count: photos.count)
        settle(on: target, velocity: velocity.width)
    }

    private func settle(on page: Int, velocity: CGFloat = 0) {
        let target = min(max(0, page), photos.count - 1)
        let pageWidth = area.width + PhotoPaging.gap
        let speed = SwipeDismissPolicy.relativeVelocity(-velocity, from: position * pageWidth, to: CGFloat(target) * pageWidth)
        withAnimation(.interpolatingSpring(Theme.Motion.settleSpring, initialVelocity: speed)) {
            position = CGFloat(target)
        }
    }

    /// A photo came on: the grid scrolls to it, and the ones next to it load.
    private func show(_ index: Int) {
        guard photos.indices.contains(index) else { return }
        onShow(photos[index])
        library.prefetch(PhotoPaging.prefetch(around: index, count: photos.count).map { photos[$0] },
                         targetSize: PhotoViewerPage.targetSize)
    }

    // MARK: Slideshow

    private struct SlideshowStep: Equatable {
        var page: Int
        var isRunning: Bool
    }

    /// Zooms in slowly on a photo, then moves on. A video moves on when it ends.
    private func runSlideshowStep() async {
        guard isSlideshow, phase == .open, dragStart == nil, pull == .zero, photos.count > 1,
              library.videoDuration(for: photos[current]) == nil else { return }
        let interval = max(3, settings[PersonalSettings.slideshowInterval])
        if !reduceMotion {
            isZoomed = false
            withAnimation(.linear(duration: interval)) { isZoomed = true }
        }
        try? await Task.sleep(for: .seconds(interval))
        guard !Task.isCancelled else { return }
        advance()
    }

    /// The next photo, crossfading over the one on screen.
    private func advance() {
        guard photos.count > 1, phase == .open else { return }
        let from = current
        var instant = Transaction()
        instant.disablesAnimations = true
        withTransaction(instant) {
            fadingPage = from
            fadeOpacity = 1
            isZoomed = false
            position = CGFloat(PhotoPaging.nextInSlideshow(after: from, count: photos.count))
        }
        withAnimation(.easeInOut(duration: 1.2)) {
            fadeOpacity = 0
        } completion: {
            if fadingPage == from { fadingPage = nil }
        }
    }
}
