import SwiftUI
import UIKit

/// Blurs and dims the whole Home Screen, wallpaper included, while an app is open over it, so it
/// comes into focus as an app closes, like iPadOS. Its icons and widgets also sit back a little,
/// which their host does (`HomeScreenHost`). A plain state that changes with the screen change, so
/// the Home Screen is drawn once for it, and Core Animation springs the blur and the dim, so they
/// keep the screen's rate while the main thread is busy with the screen change.
struct HomeRecessionEffect: ViewModifier {
    /// True while an app is open over the Home Screen.
    var receded: Bool

    func body(content: Content) -> some View {
        let geometry = AppZoomGeometry.standard
        content
            .overlay {
                HomeBlur(radius: geometry.homeBlur(receded: receded))
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
            }
            .overlay {
                HomeDim(opacity: geometry.homeDimming(receded: receded))
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
            }
    }
}

/// `Theme.Motion.screen`, a smooth half-second spring, for Core Animation, when `transaction` animates.
private func screenSpring(for transaction: Transaction) -> CASpringAnimation? {
    guard transaction.animation != nil, !transaction.disablesAnimations else { return nil }
    return CASpringAnimation(perceptualDuration: 0.5, bounce: 0)
}

/// A plain blur of the Home Screen behind it (`BackdropBlurView`). A blur over it rather than a
/// SwiftUI blur of it: that grouped the Home Screen on its own, and the Face wallpaper, itself a blur
/// of the face behind the Home Screen, had nothing left to blur and drew black.
private struct HomeBlur: UIViewRepresentable {
    var radius: CGFloat

    func makeUIView(context: Context) -> BackdropBlurView {
        let view = BackdropBlurView()
        view.isUserInteractionEnabled = false
        // Full size, so the blur clears all the way to sharp and nothing changes when it is put away.
        view.renderScale = 1
        view.radius = radius
        view.isHidden = radius == 0
        return view
    }

    func updateUIView(_ view: BackdropBlurView, context: Context) {
        view.setRadius(radius, animation: screenSpring(for: context.transaction))
    }
}

/// The black over the blurred Home Screen (`HomeDimView`).
private struct HomeDim: UIViewRepresentable {
    var opacity: CGFloat

    func makeUIView(context: Context) -> HomeDimView {
        let view = HomeDimView()
        view.isUserInteractionEnabled = false
        view.backgroundColor = .black
        view.alpha = opacity
        return view
    }

    func updateUIView(_ view: HomeDimView, context: Context) {
        view.setOpacity(opacity, animation: screenSpring(for: context.transaction))
    }
}

/// The black over the blurred Home Screen. Its opacity is sprung by Core Animation, like the blur's
/// radius under it. As a SwiftUI animation it took the main thread on every frame of the screen change.
final class HomeDimView: UIView {
    /// Springs the opacity to `value` with `animation`'s timing, from wherever it is shown now, or sets it at once without one.
    func setOpacity(_ value: CGFloat, animation: CASpringAnimation?) {
        guard value != alpha else { return }
        let from = layer.presentation()?.opacity ?? Float(alpha)
        alpha = value
        guard let animation else {
            layer.removeAnimation(forKey: Self.animationKey)
            return
        }
        animation.keyPath = "opacity"
        animation.fromValue = from
        animation.toValue = Float(value)
        layer.add(animation, forKey: Self.animationKey)
    }

    private static let animationKey = "dim"
}
