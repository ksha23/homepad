import SwiftUI

/// Debug only: the shell turns its own content a quarter for
/// `-HomePadForceLandscape`, so a portrait simulator can show the landscape
/// layout. UIKit presents a full-screen cover above the shell, unturned, so
/// this turns the editor the same way, with the same room for the home
/// indicator. Release builds never turn anything.
struct CoverForcedLandscape: ViewModifier {
    /// The home indicator's bottom safe area on Face ID iPads, as the shell leaves it.
    private static let homeIndicatorInset: CGFloat = 20

    static var isEnabled: Bool {
        #if DEBUG
        UserDefaults.standard.bool(forKey: "HomePadForceLandscape")
        #else
        false
        #endif
    }

    func body(content: Content) -> some View {
        if Self.isEnabled {
            GeometryReader { proxy in
                content
                    .safeAreaPadding(.bottom, Self.homeIndicatorInset)
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
