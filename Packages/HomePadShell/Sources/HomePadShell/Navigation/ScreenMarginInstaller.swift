import SwiftUI
import UIKit

/// Adds the screen margin to the window's safe area through the root view
/// controller's `additionalSafeAreaInsets`. SwiftUI's `safeAreaPadding` does
/// not reach UIKit-backed containers (`NavigationSplitView`, `NavigationStack`),
/// so Settings and Camera Lab would run to the bezel. UIKit's safe area reaches
/// both, and full-bleed backgrounds still ignore it.
struct ScreenMarginInstaller: UIViewRepresentable {
    let insets: EdgeInsets

    func makeUIView(context: Context) -> MarginView {
        MarginView(insets: insets)
    }

    func updateUIView(_ view: MarginView, context: Context) {
        view.insets = insets
    }

    final class MarginView: UIView {
        var insets: EdgeInsets {
            didSet { apply() }
        }

        init(insets: EdgeInsets) {
            self.insets = insets
            super.init(frame: .zero)
            isUserInteractionEnabled = false
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            apply()
        }

        private func apply() {
            guard let root = window?.rootViewController else { return }
            let target = UIEdgeInsets(top: insets.top, left: insets.leading, bottom: insets.bottom, right: insets.trailing)
            if root.additionalSafeAreaInsets != target { root.additionalSafeAreaInsets = target }
        }
    }
}
