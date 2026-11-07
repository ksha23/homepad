import HomePadUI
import SwiftUI

/// Thin touch strips along the top and bottom edges for HomeView's system swipes:
/// down from the top-left or center talks to the assistant, down from the
/// top-right opens Control Center, up from the bottom goes Home or opens the
/// app grid (the window follows the finger, `ShellNavigator.trackHomeSwipe`). The rest of the screen passes touches straight through.
struct EdgeGestureLayer: View {
    let onAssistant: () -> Void
    let onControlCenter: () -> Void
    @Environment(ShellNavigator.self) private var navigator

    /// Height of each strip. Small, so it never covers a button.
    private let stripHeight: CGFloat = 20
    /// Minimum travel before a swipe counts.
    private let threshold: CGFloat = 36

    var body: some View {
        GeometryReader { proxy in
            VStack(spacing: 0) {
                strip
                    .gesture(DragGesture(minimumDistance: 8).onEnded { value in
                        guard value.translation.height > threshold else { return }
                        if value.startLocation.x > proxy.size.width * 0.66 {
                            onControlCenter()
                        } else {
                            onAssistant()
                        }
                    })
                Color.clear.allowsHitTesting(false)
                // With an app open, the bottom edge is the app's home bar (`HomeBar`), which takes the
                // tap and the swipe there. A strip over it would swallow the tap.
                strip
                    .allowsHitTesting(navigator.screen.appID == nil)
                    .gesture(DragGesture(minimumDistance: 8, coordinateSpace: .global)
                        .onChanged { navigator.trackHomeSwipe(translation: $0.translation) }
                        .onEnded {
                            navigator.finishHomeSwipe(translation: $0.translation, predicted: $0.predictedEndTranslation,
                                                      velocity: $0.velocity)
                        })
            }
        }
        .ignoresSafeArea()
    }

    private var strip: some View {
        Color.clear
            .frame(height: stripHeight)
            .contentShape(Rectangle())
    }
}
