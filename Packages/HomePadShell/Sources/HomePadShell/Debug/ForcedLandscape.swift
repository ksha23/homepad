import HomePadUI
import SwiftUI

/// Debug only: `-HomePadForceLandscape YES` lays the whole UI out at landscape
/// size and rotates it into the portrait screen. The iPadOS 26 simulator refuses
/// programmatic rotation, so this is how landscape layouts get screenshot-tested.
/// Rotate the captured image 90 degrees clockwise to view it upright.
///
/// The content gets the 20 point bottom safe area a Face ID iPad has in
/// landscape for its home indicator, plus the screen margin the shell adds on
/// a device, so screenshots fit the way the device does.
struct ForcedLandscape: ViewModifier {
    /// The home indicator's bottom safe area on Face ID iPads.
    static let homeIndicatorInset: CGFloat = 20
    /// False for content that adds the screen margin itself (onboarding).
    var addsScreenMargin = true

    static var isEnabled: Bool {
        UserDefaults.standard.bool(forKey: "HomePadForceLandscape")
    }

    func body(content: Content) -> some View {
        if Self.isEnabled {
            GeometryReader { proxy in
                content
                    .safeAreaPadding(.bottom, Self.homeIndicatorInset)
                    .safeAreaPadding(addsScreenMargin ? Theme.Spacing.screenMargin : EdgeInsets())
                    .frame(width: proxy.size.height, height: proxy.size.width)
                    .rotationEffect(.degrees(-90))
                    .frame(width: proxy.size.width, height: proxy.size.height)
            }
            .ignoresSafeArea()
        } else {
            content
        }
    }
}
