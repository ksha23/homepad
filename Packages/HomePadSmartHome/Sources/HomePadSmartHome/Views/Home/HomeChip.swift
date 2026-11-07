import HomePadCore
import HomePadUI
import SwiftUI

/// The Home app's chip: a glass capsule at least `tapTarget` tall, like
/// `GlassCapsuleButton`'s large size, with Title 3 text from arm's length and
/// Title 2 from across the room. Status chips, sensor readings and favorite
/// scenes all use it, so they line up in a row with the room picker.
struct HomeChipModifier: ViewModifier {
    @Environment(\.proximity) private var proximity
    /// Takes the pressed look of a button.
    var isInteractive = false

    func body(content: Content) -> some View {
        content
            .font(proximity >= .mid ? .title3.weight(.semibold) : .title2.weight(.semibold))
            .lineLimit(1)
            .padding(.horizontal, Theme.Spacing.l)
            .frame(minHeight: Theme.Size.tapTarget)
            .contentShape(Capsule())
            .glassEffect(isInteractive ? .regular.interactive() : .regular, in: .capsule)
    }
}

extension View {
    /// Draws this as a Home app chip (`HomeChipModifier`).
    func homeChip(isInteractive: Bool = false) -> some View {
        modifier(HomeChipModifier(isInteractive: isInteractive))
    }
}
