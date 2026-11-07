import HomePadCore
import HomePadUI
import SwiftUI

/// A symbol on a small circle, the icon of every accessory tile, accessory row
/// and scene button. At rest it is the page's text color on a faint circle of
/// it. Lit, the circle turns a subtle lighter control surface with a dark symbol
/// so it reads cleanly over the tile's colored fill, matching Apple Home's tiles.
///
///     IconBadge(symbol: "lightbulb.fill", color: isOn ? .black.opacity(0.8) : .primary, isLit: isOn, diameter: 40)
struct IconBadge: View {
    /// The size in full-width rows (widgets, Control Center, group members) and small widgets.
    static let rowDiameter: CGFloat = 40
    /// The size in scene rows and in tiles short of room.
    static let compactDiameter: CGFloat = 36

    let symbol: String
    /// The symbol's color: dark over colored fills when lit, or the text color when off.
    var color: Color = .primary
    /// Draws the lighter control circle for an accessory that is on.
    var isLit = false
    let diameter: CGFloat
    var font: Font = .title3.weight(.semibold)

    @Environment(\.colorScheme) private var colorScheme

    private var isLight: Bool { colorScheme == .light }

    var body: some View {
        let foreground = isLit ? Color.black.opacity(0.8) : color
        let circleFill = isLit
            ? Color.white.opacity(isLight ? 0.35 : 0.22)
            : Color.primary.opacity(isLight ? 0.08 : 0.14)

        Image(systemName: symbol)
            .font(font)
            .symbolRenderingMode(.hierarchical)
            .foregroundStyle(foreground)
            // A bulb fills, a shackle opens, a garage door rolls up. Plays when the
            // symbol changes inside an animation, as tiles and rows animate their state.
            .contentTransition(.symbolEffect(.replace.magic(fallback: .replace.downUp)))
            .frame(width: diameter, height: diameter)
            .background(Circle().fill(circleFill))
    }
}

extension IconBadge {
    /// An accessory's state-aware symbol, dark on a lighter circle while it is on.
    init(accessory: HomeAccessory, diameter: CGFloat, font: Font = .title3.weight(.semibold)) {
        let isActive = AccessoryPresentation.isActive(accessory)
        self.init(
            symbol: AccessoryPresentation.symbol(for: accessory),
            color: isActive ? Color.black.opacity(0.8) : .primary,
            isLit: isActive, diameter: diameter, font: font
        )
    }
}
