import HomePadCore
import HomePadUI
import SwiftUI

/// Frames the One Photo face's photo, like setting a Lock Screen wallpaper: the
/// face as it will look on the wall, full screen, where a pinch zooms and a
/// drag moves the photo. The photo always covers the screen. Cancel puts the
/// framing back as it was.
struct PhotoFramingView: View {
    @Binding var configuration: FaceConfiguration

    @Environment(\.dismiss) private var dismiss
    @Environment(FacesRuntime.self) private var runtime
    @State private var original: FaceConfiguration?
    /// The framing when the current pinch or drag began.
    @State private var start: PhotoFraming?
    /// How far the current drag has moved, and how much the current pinch has zoomed.
    @State private var translation: CGSize = .zero
    @State private var magnification: CGFloat = 1
    @State private var isDragging = false
    @State private var isPinching = false
    /// The photo's size, for turning a drag into a move of the photo.
    @State private var imageSize: CGSize?

    var body: some View {
        GeometryReader { proxy in
            // Laid out at the wall face's own size, so the photo crops and the
            // depth effect decides exactly as on the wall.
            let canvas = runtime.wallCanvas ?? proxy.size
            FaceThumbnail(faceID: configuration.faceID, configuration: configuration, isLive: true,
                          canvas: canvas, proximity: .far)
                .frame(width: proxy.size.width, height: proxy.size.height)
                .overlay {
                    Color.clear
                        .contentShape(Rectangle())
                        .gesture(drag(canvas: canvas, shown: proxy.size))
                        .simultaneousGesture(pinch(canvas: canvas))
                        .accessibilityLabel("Photo")
                        .accessibilityHint("Pinch to zoom, drag to move")
                }
        }
        .ignoresSafeArea()
        .overlay(alignment: .top) {
            AppHeader("Frame Photo", onClose: cancel) {
                GlassCapsuleButton("Reset", systemImage: "arrow.counterclockwise") { reset() }
                GlassCapsuleButton("Done", isProminent: true) { dismiss() }
            }
            .padding([.horizontal, .top], Theme.Spacing.l)
            .background(alignment: .top) {
                // Keeps the title readable over a bright photo.
                LinearGradient(colors: [.black.opacity(0.5), .clear], startPoint: .top, endPoint: .bottom)
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
            }
        }
        .overlay(alignment: .bottom) {
            GlassPill("Pinch to zoom, drag to move", systemImage: "hand.draw")
                .padding(.bottom, Theme.Spacing.l)
                .allowsHitTesting(false)
        }
        .onAppear { original = configuration }
        .task {
            imageSize = configuration.values[PhotoSourcePage.singleKey].flatMap(PhotoLibrarySource.pixelSize(localIdentifier:))
        }
        .preferredColorScheme(.dark)
    }

    private var framing: PhotoFraming {
        PhotoFraming(values: configuration.values)
    }

    // A drag and a pinch, attached separately so a drag that starts first
    // cannot hold the touches the pinch needs. Both measure from the framing
    // when the first finger came down, so they combine while both are active.

    /// `shown` is the size on screen, `canvas` the size the face is laid out
    /// at, so a drag moves the photo exactly as far as the finger.
    private func drag(canvas: CGSize, shown: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 1)
            .onChanged { value in
                isDragging = true
                let scale = shown.width > 0 ? canvas.width / shown.width : 1
                translation = CGSize(width: value.translation.width * scale, height: value.translation.height * scale)
                apply(viewSize: canvas)
            }
            .onEnded { _ in
                isDragging = false
                finishIfIdle()
            }
    }

    private func pinch(canvas: CGSize) -> some Gesture {
        MagnifyGesture()
            .onChanged { value in
                isPinching = true
                magnification = value.magnification
                apply(viewSize: canvas)
            }
            .onEnded { _ in
                isPinching = false
                finishIfIdle()
            }
    }

    private func apply(viewSize: CGSize) {
        guard let imageSize else { return }
        let base = start ?? framing
        if start == nil { start = base }
        base.zoomed(by: magnification)
            .moved(by: translation, imageSize: imageSize, viewSize: viewSize)
            .write(to: &configuration.values)
    }

    private func finishIfIdle() {
        guard !isDragging, !isPinching else { return }
        start = nil
        translation = .zero
        magnification = 1
    }

    private func reset() {
        withAnimation(Theme.Motion.standard) { PhotoFraming.clear(from: &configuration.values) }
    }

    private func cancel() {
        if let original { configuration = original }
        dismiss()
    }
}
