import HomePadCore
import HomePadUI
import SwiftUI

/// A Home face tile in the theme's colors, filled with its "on" color from the
/// leading edge to an accessory's level, the way the Home widget's tiles show
/// it: a light dimmed to 40 percent fills 40 percent of the tile. The rest of
/// the tile keeps the "off" look, and text is drawn in each part's own ink.
struct HomeLevelTile<Content: View>: View {
    let palette: FacePalette
    /// How much of the tile is "on", from 0 to 1.
    let fill: Double
    /// The tile's content for an ink: true draws it in the "on" colors.
    @ViewBuilder let content: (_ isOn: Bool) -> Content

    var body: some View {
        let fill = min(max(fill, 0), 1)
        let isFull = fill >= 1
        GlassTile(isHighlighted: true, tint: HomeTileInk.fill(palette: palette, isOn: isFull)) { content(isFull) }
            .overlay {
                if fill > 0, !isFull {
                    GlassTile(isHighlighted: true, tint: HomeTileInk.fill(palette: palette, isOn: true)) { content(true) }
                        .mask(alignment: .leading) {
                            Rectangle().scaleEffect(x: fill, anchor: .leading)
                        }
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
            }
            .animation(.smooth, value: fill)
    }
}
