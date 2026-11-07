import HomePadCore
import SwiftUI

/// Shared look for every module. Keep additions backward compatible:
/// other packages build against these names.
public enum Theme {
    /// Corner radii. Each kind of element always uses its own, and a shape
    /// nested in another takes the outer radius less the inset between them,
    /// so the corners run parallel. See DESIGN.md for when to use each.
    public enum Radius {
        /// Tile-level surfaces: widgets, Control Center modules, `GlassTile`,
        /// `GlassPanel`, `GlassBanner`, glass panels that sit straight on a
        /// screen, camera views and hero artwork.
        public static let tile: CGFloat = 28
        /// Rows and cards smaller than a tile, on a screen or a panel: list
        /// rows, option cards, face previews, shelf artwork, chat bubbles and
        /// text fields.
        public static let card: CGFloat = 22
        /// Small images under about 80 points (mini player art, queue rows,
        /// attachments) and dense image grids. Also the smallest radius a
        /// nested shape takes, so nothing inside a container turns square.
        public static let thumbnail: CGFloat = 12
        /// Anything in a `GlassTile`'s padding: controls (Favorites rows, scene
        /// tiles, timer presets), artwork and thumbnails. The tile's radius
        /// less its padding, so the corners run parallel to the tile's.
        /// `GlassTile` hands it to its content as `\.controlCornerRadius`.
        public static let tileControl: CGFloat = concentric(in: tile, inset: Spacing.m)
        /// Capsules and round artwork. Prefer `Capsule()` and `Circle()`.
        public static let pill: CGFloat = 999

        /// The radius for a shape inset by `inset` inside a container whose
        /// corners have radius `outer`: the outer radius less the inset, so the
        /// two corners run parallel, and never less than `thumbnail`.
        ///
        ///     Theme.Radius.concentric(in: Theme.Radius.tile, inset: Theme.Spacing.l)
        public static func concentric(in outer: CGFloat, inset: CGFloat) -> CGFloat {
            max(outer - inset, thumbnail)
        }

        /// The corner radius of an `AppIcon` or `SettingsIcon` whose edge is
        /// `size` points long: 26% of it.
        public static func icon(_ size: CGFloat) -> CGFloat {
            size * 0.26
        }
    }

    public enum Spacing {
        public static let xs: CGFloat = 6
        public static let s: CGFloat = 10
        public static let m: CGFloat = 16
        public static let l: CGFloat = 24
        public static let xl: CGFloat = 36
        /// Between controls that share a tile (Favorites rows, scene tiles, timer
        /// presets, notes), the same in every widget so none looks more cramped.
        public static let controlGap: CGFloat = s
        /// Between the rows of a sidebar of sections (Settings, Music). With
        /// rows `Size.tapTarget` tall, a finger at arm's length lands on one
        /// row and never on the edge of the next.
        public static let sidebarRowGap: CGFloat = s
        /// Extra room around the whole screen, so content never crowds the
        /// iPad's thin bezel. The shell adds it once to the window's safe area
        /// (so UIKit-backed navigation gets it too), and every screen pads `l`
        /// inside it: content sits 64 points from the sides and 44 from the top
        /// everywhere. Full-bleed backgrounds still reach the edge.
        public static let screenMargin = EdgeInsets(top: 20, leading: 40, bottom: 12, trailing: 40)
        /// Where content starts on every screen, from the bezel: the shell's
        /// margin plus a screen's `l` padding (64 at the sides, 44 top and
        /// bottom). Faces draw outside the shell's margin, so they inset their
        /// content by this through `\.faceInsets`.
        public static let screenContent = EdgeInsets(
            top: screenMargin.top + l, leading: screenMargin.leading + l,
            bottom: screenMargin.top + l, trailing: screenMargin.trailing + l
        )
    }

    /// The red palette used in night mode, like HomeView's monochrome red widgets.
    public static let nightRed = Color(red: 0.85, green: 0.12, blue: 0.10)

    /// Accent per accessory kind for tiles.
    public static func tint(for kind: AccessoryKind) -> Color {
        switch kind {
        case .light: .yellow
        case .thermostat: .orange
        case .lock: .teal
        case .fan, .airPurifier, .cover, .garageDoor: .cyan
        case .camera, .doorbell: .blue
        case .mediaPlayer: .pink
        case .securitySystem: .red
        default: .gray
        }
    }
}

public extension Font {
    /// Huge rounded numerals for clocks and thermostats seen from across the room.
    static func display(_ size: CGFloat, weight: Font.Weight = .semibold) -> Font {
        .system(size: size, weight: weight, design: .rounded)
    }
}

public extension EnvironmentValues {
    /// Corner radius for controls drawn on a surface: `Theme.Radius.card` on
    /// their own, `Theme.Radius.tileControl` inside a `GlassTile`.
    @Entry var controlCornerRadius: CGFloat = Theme.Radius.card

    /// Where a face's content starts from the face's own edges, so faces line
    /// up with the rest of HomePad. The ambient screen adds its burn-in overscan.
    @Entry var faceInsets: EdgeInsets = Theme.Spacing.screenContent

    /// The part of `faceInsets.top` the Now Playing pill takes while the face
    /// shows it (`Theme.Size.faceNowPlayingRoom`), otherwise zero. A face's
    /// widgets keep their place whether or not it shows, so their grid is
    /// laid out from the insets without it.
    @Entry var faceNowPlayingRoom: CGFloat = 0

    /// True for content drawn over a control's colored fill, false over its
    /// surface. `levelFill` sets it, `fillAwareForeground` reads it.
    @Entry var isOverFill = false
}
