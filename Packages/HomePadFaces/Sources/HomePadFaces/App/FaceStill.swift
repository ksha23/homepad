import HomePadCore
import SwiftUI
import UIKit

/// A face on a card, as a picture (`FaceStills`). While its picture is current
/// it is that picture and nothing else: no timelines, tasks, widgets or glass.
/// When it has none, or the minute or the look has changed, it waits for its
/// turn, builds the live face and takes a new picture of it, then lets the
/// live face go. Until then it shows the picture it had, or, the first time,
/// black, the color a face is drawn on, and then the live face itself. Only
/// a card on screen builds: one scrolled out of sight, or covered by the
/// editor or the gallery (`\.facesPausesStills`), keeps the picture it has.
struct FaceStill<Face: View>: View {
    let look: FaceStills.Look
    /// The card's size.
    let size: CGSize
    /// The live face, laid out and scaled to `size`.
    @ViewBuilder let face: () -> Face

    @Environment(FacesRuntime.self) private var runtime
    @Environment(\.facesPausesStills) private var isPaused
    /// This card, for its turn to build. Two cards can show the same look.
    @State private var card = UUID()
    /// True from the card's turn until its picture is taken.
    @State private var isLive = false
    /// False while the card is scrolled out of sight.
    @State private var isOnScreen = true

    /// How much of a card shows for it to count as on screen: any of it.
    private static var onScreenShare: Double { 0.01 }

    var body: some View {
        let stills = runtime.stills
        // Ticks on whole minutes, as the faces' own clocks do, so a picture
        // goes out of date when the face would have redrawn.
        TimelineView(FaceSchedule(cadence: .minute)) { context in
            let minute = FaceStills.minute(of: context.date)
            let still = stills.still(for: look)
            let need = Need(look: look, isCurrent: still?.minute == minute, isTurn: stills.building == card, isLive: isLive,
                            isHidden: isPaused || !isOnScreen)
            ZStack {
                if isLive {
                    FaceStillCapture(size: size, onBuilt: { stills.didBuild(card) }) { image in
                        stills.store(image, for: look, minute: minute)
                        isLive = false
                    } face: {
                        face()
                    }
                }
                if let still {
                    // Over the live face while a new picture is taken, so the card never flickers.
                    Image(uiImage: still.image)
                        .resizable()
                } else if !isLive {
                    Color.black
                }
            }
            .onChange(of: need) { _, need in decide(need) }
            // Again each time the card comes back on screen, since leaving gave up its turn.
            .onAppear { decide(need) }
        }
        .onScrollVisibilityChange(threshold: Self.onScreenShare) { isOnScreen = $0 }
        .onDisappear {
            runtime.stills.cancel(card)
            isLive = false
        }
    }

    /// What the card has and what it is waiting for.
    private struct Need: Equatable {
        var look: FaceStills.Look
        var isCurrent: Bool
        var isTurn: Bool
        var isLive: Bool
        /// Scrolled out of sight or covered: it waits until it shows.
        var isHidden: Bool
    }

    private func decide(_ need: Need) {
        let stills = runtime.stills
        if need.isCurrent {
            // Its own picture, or one another card with the same look took meanwhile.
            stills.cancel(card)
            isLive = false
        } else if need.isLive {
            // Building, or waiting for the face to load before its picture.
        } else if need.isHidden {
            stills.cancel(card)
        } else if need.isTurn {
            isLive = true
        } else {
            stills.request(card)
        }
    }
}

/// Builds a live face in a host of its own and takes a picture of it once
/// it is on screen and has loaded what it shows (`FaceLoadingKey`).
///
/// The face has a UIKit host of its own so the picture is of the face
/// alone, drawn by the render server as on screen (`drawHierarchy`), glass
/// included. It takes the card's whole environment, so it is drawn exactly
/// as it would be in the card.
private struct FaceStillCapture<Face: View>: UIViewControllerRepresentable {
    let size: CGSize
    let onBuilt: () -> Void
    let onPicture: (UIImage) -> Void
    @ViewBuilder let face: () -> Face

    @Environment(\.self) private var environment

    func makeUIViewController(context: Context) -> CaptureController {
        let controller = CaptureController(rootView: AnyView(EmptyView()))
        controller.safeAreaRegions = []
        controller.sizingOptions = []
        controller.view.backgroundColor = .clear
        controller.view.isUserInteractionEnabled = false
        // The card is one element for VoiceOver, named for its face.
        controller.view.accessibilityElementsHidden = true
        update(controller)
        return controller
    }

    func updateUIViewController(_ controller: CaptureController, context: Context) {
        update(controller)
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiViewController: CaptureController, context: Context) -> CGSize? {
        size
    }

    private func update(_ controller: CaptureController) {
        controller.onPicture = onPicture
        controller.rootView = AnyView(
            face()
                .environment(\.self, environment)
                .frame(width: size.width, height: size.height, alignment: .topLeading)
                .backgroundPreferenceValue(FaceLoadingKey.self) { [weak controller] isLoading in
                    Color.clear
                        .onAppear(perform: onBuilt)
                        .task(id: isLoading) {
                            guard !isLoading else { return }
                            // A frame later the face is committed and can be drawn as it is.
                            await NextFrame.wait()
                            controller?.takePicture()
                        }
                }
        )
    }

    final class CaptureController: UIHostingController<AnyView> {
        var onPicture: ((UIImage) -> Void)?

        func takePicture() {
            guard let onPicture, view.window != nil, view.bounds.width > 0, view.bounds.height > 0 else { return }
            let format = UIGraphicsImageRendererFormat(for: traitCollection)
            format.opaque = false
            let image = UIGraphicsImageRenderer(bounds: view.bounds, format: format).image { _ in
                // As committed, without asking for screen updates. Asking for them made every host in
                // the window lay out and render at once, 40 to 70 ms for each picture.
                _ = view.drawHierarchy(in: view.bounds, afterScreenUpdates: false)
            }
            self.onPicture = nil
            onPicture(image)
        }
    }
}

/// Waits for the screen's next frame, by which time what the last update
/// built has been committed.
@MainActor
private enum NextFrame {
    static func wait() async {
        await withCheckedContinuation { continuation in
            Waiter(continuation).start()
        }
    }

    private final class Waiter: NSObject {
        private var continuation: CheckedContinuation<Void, Never>?
        private var link: CADisplayLink?

        init(_ continuation: CheckedContinuation<Void, Never>) {
            self.continuation = continuation
        }

        func start() {
            // The link keeps the waiter alive until it fires.
            let link = CADisplayLink(target: self, selector: #selector(tick))
            link.add(to: .main, forMode: .common)
            self.link = link
        }

        @objc private func tick() {
            link?.invalidate()
            link = nil
            continuation?.resume()
            continuation = nil
        }
    }
}
