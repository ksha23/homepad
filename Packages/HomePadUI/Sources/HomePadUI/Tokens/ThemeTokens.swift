import SwiftUI

// Typography, motion and size tokens. See DESIGN.md for when to use each.

public extension Theme {
    /// Animation curves. HomePad moves calmly: nothing bounces hard, nothing snaps.
    enum Motion {
        /// Default for state changes inside a screen (toggles, selection, small layout shifts).
        public static let standard: Animation = .smooth(duration: 0.35)
        /// Screen-level transitions (face to Home Screen, opening an app, panels).
        public static let screen: Animation = .smooth(duration: screenDuration)
        /// How long `screen` takes, for work that has to wait until a screen has finished changing.
        public static let screenDuration: Double = 0.5
        /// Interactive surfaces that follow a finger and settle (sliders, sheets, drags).
        public static let settle: Animation = .spring(response: 0.42, dampingFraction: 0.86)
        /// `settle` as a spring, for a surface let go mid-drag, which carries on
        /// at the finger's speed (`.interpolatingSpring(_:initialVelocity:)`).
        public static let settleSpring = Spring(response: 0.42, dampingRatio: 0.86)
        /// Something following a finger closely, such as a page being swiped,
        /// that smoothly takes over a page still settling from the last swipe.
        public static let follow: Animation = .interactiveSpring(response: 0.15, dampingFraction: 0.86)
        /// Someone walking up or away: a face or widget moving between its far
        /// and near layouts. One curve for the whole change, so the big fact
        /// glances smaller as the detail fades in, as one move.
        public static let proximity: Animation = .spring(proximitySpring)
        /// `proximity` as a spring, for motion worked out frame by frame from
        /// the clock (Flow's drops), which no animation drives.
        public static let proximitySpring = Spring.smooth(duration: 0.7)
        /// Slow ambient drift (burn-in shift, wallpaper, presence-driven fades).
        public static let ambient: Animation = .easeInOut(duration: 2.5)
    }

    /// Minimum sizes for touch targets and glanceable elements. See "Walk-up
    /// sizes" in DESIGN.md for which one a control takes.
    enum Size {
        /// Smallest touch target (Apple HIG). Only for dense chrome used up
        /// close (the top pills, items in a toolbar group, editor handles), never
        /// for a control on a walk-up screen.
        public static let minTapTarget: CGFloat = 44
        /// Every item in a header toolbar: icon buttons, text buttons, menus,
        /// groups and the close button. Apple's 44 point bar items plus a little
        /// for a display tapped at arm's length.
        public static let toolbarItem: CGFloat = 48
        /// The walk-up minimum: the smallest a control on an app screen, panel,
        /// widget or Control Center may be, in its short dimension. Chips, list
        /// rows, sidebar rows, segment options and round buttons all reach it.
        public static let tapTarget: CGFloat = 64
        /// Round toggles and avatar buttons in system surfaces.
        public static let roundControl: CGFloat = 72
        /// The main control of a screen: play, shutter, answer the doorbell.
        public static let heroControl: CGFloat = 88
        /// Home Screen app icon on an 11-inch iPad. Larger screens scale up from it.
        public static let appIcon: CGFloat = 96
        /// The width headers leave empty at their top center, where the shell
        /// draws the Now Playing pill. The compact pill is 100 to 120 points
        /// wide, so this is 128 points of pill and `Spacing.l` on each side.
        public static let nowPlayingZone: CGFloat = 176
        /// How far a face's content moves down while the face shows the Now
        /// Playing pill (`\.faceNowPlayingRoom`): the full pill's height and a
        /// gap, so the layout does not move again when someone walks up and
        /// the pill grows.
        public static let faceNowPlayingRoom: CGFloat = 52 + Spacing.m
        /// The widest the Now Playing pill gets on a face, up close: its
        /// artwork, a title of at most 260 points and the waveform. A face's
        /// widget grid keeps the cells under it free.
        public static let faceNowPlayingWidth: CGFloat = 364
        /// The profile button: the avatar at the right of the Home Screen's
        /// header, and the same avatar in the same spot on a face. About two
        /// thirds of a Home Screen app icon, as on HomeView.
        public static let profileButton: CGFloat = tapTarget
        /// How far the profile button sits from the screen's top and trailing
        /// edges, on the Home Screen and on a face: the content margin, so it
        /// sits as far from the top as from the side.
        public static let profileButtonInset: CGFloat = Spacing.screenContent.trailing
    }
}

public extension Font {
    /// Big screen titles ("Settings", "Home"). Used by `AppScreen`.
    static let screenTitle: Font = .largeTitle.bold()

    /// Glanceable headline readable from across a room, like the Home Screen greeting.
    static let glanceTitle: Font = .system(.largeTitle, design: .rounded).weight(.bold)

    /// Secondary glanceable line under a `glanceTitle`, like the date and time.
    static let glanceSubtitle: Font = .system(.title2, design: .rounded).weight(.semibold)

    /// Title inside a tile, row or card: the name of a thing ("Front Door",
    /// "Groove Salad"). Title 3, the smallest primary text on a walk-up
    /// surface, about the size HomeView draws its row and button text.
    static let tileTitle: Font = .title3.weight(.semibold)

    /// The secondary line in a tile, row or card: status, subtitle, time or
    /// place ("Locked", "Ambient, Downtempo"). Body, the smallest text that
    /// carries information on a walk-up surface.
    static let tileDetail: Font = .body

    /// A value inside a tile ("72°", "Locked", "8:30").
    static let tileValue: Font = .system(.title2, design: .rounded).weight(.semibold)
}
