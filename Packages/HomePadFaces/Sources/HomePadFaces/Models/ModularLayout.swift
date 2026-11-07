import CoreGraphics
import HomePadCore
import HomePadUI
import SwiftUI

/// Where the Modular face puts its parts, worked out from the space it has,
/// so the face fills any iPad in either orientation and never runs off it.
///
/// The info panel is always HomeView's info face: the date and the clock on
/// top, the day's events and the weather below. It fills the area inside the
/// face insets. With widgets, `HostedFace` moves those insets clear of the
/// face's widget area, so the panel sits beside a column of widgets in
/// landscape, like the iPad's widget column, and over two rows of them in
/// portrait. With no widgets the info panel takes the whole screen.
///
/// Like HomeView, the face is simpler and larger from across the room: there
/// the date and the clock fill the whole info panel (`heroLayout`). Up close
/// they move into its top half, and the events and the weather fade in under
/// them. Widgets keep their place at every distance.
struct ModularLayout: Equatable {
    /// Where content stops short of the edges: the face insets, clear of the widgets.
    let insets: EdgeInsets
    /// The space inside the insets that the parts fill.
    let content: CGRect
    /// Space between parts.
    let gap: CGFloat
    /// Body text size for events and weather details.
    let textSize: CGFloat
    /// The info panel: hero on top, events and weather below.
    let info: CGRect
    /// The date and the clock.
    let hero: CGRect
    /// The events and the weather.
    let lower: CGRect

    init(size: CGSize, insets: EdgeInsets = Theme.Spacing.screenContent) {
        let minSide = max(min(size.width, size.height), 1)
        self.insets = insets
        gap = Self.clamp(minSide * 0.032, 14, 36)
        textSize = Self.clamp(minSide * 0.036, 20, 40)

        let content = CGRect(
            x: insets.leading, y: insets.top,
            width: max(size.width - insets.leading - insets.trailing, 1),
            height: max(size.height - insets.top - insets.bottom, 1)
        )
        self.content = content
        info = content
        let heroHeight = (info.height - gap) * 0.5
        hero = CGRect(x: info.minX, y: info.minY, width: info.width, height: heroHeight)
        lower = CGRect(x: info.minX, y: hero.maxY + gap, width: info.width, height: info.maxY - hero.maxY - gap)
    }

    /// The date and the clock at a distance. From across the room they fill
    /// the whole info panel, the date above the dial when that makes the dial
    /// larger (a tall or square panel). Up close they sit in `hero`.
    func heroLayout(isDigital: Bool, isNear: Bool) -> ModularHeroLayout {
        if isDigital { return .digital(in: isNear ? hero : info) }
        if isNear { return .analog(in: hero, gap: gap) }
        let beside = ModularHeroLayout.analog(in: info, gap: gap)
        let stacked = ModularHeroLayout.analog(in: info, gap: gap, stacked: true)
        return stacked.clock.width > beside.clock.width ? stacked : beside
    }

    /// A row split in two by the gap, the leading part taking `leadingFraction` of the width.
    func split(_ row: CGRect, leadingFraction: CGFloat = 0.5) -> (leading: CGRect, trailing: CGRect) {
        let available = row.width - gap
        let width = available * leadingFraction
        return (CGRect(x: row.minX, y: row.minY, width: width, height: row.height),
                CGRect(x: row.minX + width + gap, y: row.minY, width: available - width, height: row.height))
    }

    private static func clamp(_ value: CGFloat, _ low: CGFloat, _ high: CGFloat) -> CGFloat {
        min(max(value, low), high)
    }
}
