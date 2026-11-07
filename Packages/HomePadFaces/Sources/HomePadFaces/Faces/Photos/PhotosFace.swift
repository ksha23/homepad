import HomePadCore
import HomePadUI
import SwiftUI

/// `faces.photos`: a slow Ken Burns slideshow of favorites, an album (iCloud
/// Shared Albums included) or featured photos, with HomeView's depth effect:
/// big numerals drawn behind the people in the picture. With One Photo it
/// shows a single photo that never changes or moves.
///
/// From across the room the face is the photo and a big time
/// (`PhotoClockLayout`). Walking up, the time glances smaller and the date
/// fades in. Widgets sit in the face's widget area at every distance: the
/// bottom row in landscape and the bottom three rows in portrait, where the
/// time never reaches. With widgets, the time keeps above them through the
/// face insets `HostedFace` hands the face.
struct PhotosFace: View {
    static let source = FaceOption(id: "source", title: "Photos", kind: .custom { configuration in
        AnyView(PhotoSourcePage(configuration: configuration))
    }, defaultValue: PhotoSourceKind.featured.rawValue)
    static let style = FaceOption.style([
        FaceChoice("depth", "Depth", systemImage: "square.3.layers.3d"),
        FaceChoice("classic", "Classic", systemImage: "photo"),
    ])
    /// The time's color: a tint from the photo, or one of the light text
    /// colors (`FaceTextColor.light`, stored by raw value), which read over a
    /// photo with the clock's shadow. "photo" and "white" are the original choices.
    static let tint = FaceOption(id: "tint", title: "Color", kind: .choices(
        [FaceChoice("photo", "From Photo", systemImage: "eyedropper")]
            + FaceTextColor.light.map { FaceChoice($0.rawValue, $0.title, systemImage: "circle.fill") }
    ), defaultValue: "photo")
    static let interval = FaceOption(id: "interval", title: "Timing", kind: .choices([
        FaceChoice("20", "Every 20 Seconds"), FaceChoice("60", "Every Minute"),
        FaceChoice("300", "Every 5 Minutes"), FaceChoice("1800", "Every 30 Minutes"), FaceChoice("3600", "Every Hour"),
    ]), defaultValue: "60", cardStyle: .symbol, isShown: { configuration in
        // One Photo never changes, so it has no timing.
        configuration.value(PhotosFace.source) != PhotoSourceKind.single.rawValue
    })
    /// Widgets along the bottom, under the time: one row in landscape, three
    /// in portrait, where the time is only as tall as the width allows.
    static let widgetArea = FaceWidgetArea(landscape: .bottom(rows: 1), portrait: .bottom(rows: 3))

    static let definition = FaceDefinition(
        id: "faces.photos", title: "Photos", summary: "Your photos with the time tucked behind the people in them",
        systemImage: "photo.on.rectangle", sortOrder: 10, options: [source, style, tint, interval],
        widgets: .besideWidgets(widgetArea, legacySize: .medium)
    ) { PhotosFace() }

    @Environment(\.faceInsets) private var faceInsets
    @Environment(\.faceKeepClear) private var keepClear

    @Environment(\.faceConfiguration) private var configuration
    @Environment(FacesRuntime.self) private var runtime
    @Environment(\.isThumbnail) private var isThumbnail
    @Environment(\.displayScale) private var displayScale
    @Environment(\.proximity) private var proximity
    @State private var slideshow = PhotoSlideshow()
    @State private var reloadToken = 0

    var body: some View {
        let isNear = proximity >= .mid
        GeometryReader { proxy in
            // With widgets the insets end above them, so the time keeps clear
            // of them whoever is recognized and at every distance.
            let clock = clockLayout(size: proxy.size)
            ZStack {
                Color.black
                if let frame = slideshow.frame {
                    PhotoSlideView(
                        frame: frame,
                        motion: query.isStill ? .still : .make(seed: slideshow.slideNumber, subject: frame.sample?.subjectBounds),
                        duration: isThumbnail || query.isStill ? 0 : intervalSeconds + 3,
                        wantsDepth: configuration.value(Self.style) == "depth",
                        timeColor: FaceTextColor(rawValue: configuration.value(Self.tint)),
                        viewSize: proxy.size,
                        framing: query.isStill ? PhotoFraming(values: configuration.values) : PhotoFraming(),
                        clock: clock
                    )
                    .id("\(frame.id)#\(slideshow.slideNumber)")
                    .transition(.opacity)
                }
                if isNear, !isThumbnail {
                    // Above the widgets when there are any, since the insets end there.
                    PhotoAccessCard(status: slideshow.status) { reloadToken += 1 }
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                        .padding(faceInsets)
                        .faceForeground()
                        .transition(.proximityDetail)
                }
            }
            // A thumbnail shows one photo and never advances, so it shows it at once.
            // Faded in, the picture of a card was taken of the fade's first frames.
            .animation(isThumbnail ? nil : .easeInOut(duration: 1.6), value: slideshow.slideNumber)
            .task(id: TaskKey(query: query, interval: intervalSeconds, pixels: maxPixel(for: proxy.size), reload: reloadToken)) {
                await slideshow.run(query: query, interval: intervalSeconds, maxPixel: maxPixel(for: proxy.size),
                                    advances: !isThumbnail, processor: runtime.photoProcessor)
            }
        }
        .ignoresSafeArea()
        // Glass widgets read the photo on screen from its average color, and
        // black until the first one loads.
        .backdropTone(slideshow.frame?.tint.tone ?? .black)
        .faceIsLoading(!slideshow.hasLoaded)
    }

    /// Where the time goes at each distance, for the chosen style.
    private func clockLayout(size: CGSize) -> PhotoClockLayout {
        let uses24Hour = ClockText.localeUses24Hour()
        if configuration.value(Self.style) == "depth" {
            // Centered like HomeView's while no widgets take the bottom. Above
            // them it starts at the top, where it has the most room.
            return .depth(viewSize: size, insets: faceInsets, metrics: .depth(uses24Hour: uses24Hour),
                          isCentered: keepClear.bottom == 0)
        }
        return .classic(viewSize: size, insets: faceInsets, metrics: .rounded(uses24Hour: uses24Hour))
    }

    private var intervalSeconds: TimeInterval {
        TimeInterval(configuration.value(Self.interval)) ?? 60
    }

    private var query: PhotoQuery {
        PhotoQuery(
            source: PhotoSourceKind(rawValue: configuration.value(Self.source)) ?? .featured,
            albumID: configuration.values[PhotoSourcePage.albumIDKey],
            pickedIDs: configuration.items[PhotoSourcePage.pickedKey] ?? [],
            singleID: configuration.values[PhotoSourcePage.singleKey]
        )
    }

    /// Enough pixels for the screen plus the Ken Burns zoom, smaller for thumbnails.
    private func maxPixel(for size: CGSize) -> Int {
        if isThumbnail { return 640 }
        return min(Int(max(size.width, size.height) * displayScale * 1.12), 2600)
    }

    private struct TaskKey: Hashable {
        var query: PhotoQuery
        var interval: TimeInterval
        var pixels: Int
        var reload: Int
    }
}

/// Up close, explains why demo pictures are showing and offers to fix it.
private struct PhotoAccessCard: View {
    let status: PhotoSlideshow.Status
    let onAllowed: () -> Void

    var body: some View {
        switch status {
        case .library:
            EmptyView()
        case .needsAccess:
            card(title: "Show Your Photos Here",
                 message: "HomePad can show your favorites, a shared album or photos you pick. Photos stay on this iPad.",
                 action: "Allow Photos") {
                Task { if await PhotoLibrarySource.requestAccess() { onAllowed() } }
            }
        case .denied:
            card(title: "Photos Access Is Off",
                 message: "Turn on Photos for HomePad in Settings, Privacy and Security, Photos.", action: nil) {}
        case .empty:
            card(title: "No Photos Yet",
                 message: "This source has no photos. Choose another one in the Faces app.", action: nil) {}
        }
    }

    private func card(title: String, message: String, action: String?, perform: @escaping () -> Void) -> some View {
        GlassBanner(systemImage: "photo.on.rectangle.angled", tint: .indigo, title: title, subtitle: message) {
            EmptyView()
        } actions: {
            if let action {
                GlassCapsuleButton(action, isProminent: true, action: perform)
            }
        }
    }
}
