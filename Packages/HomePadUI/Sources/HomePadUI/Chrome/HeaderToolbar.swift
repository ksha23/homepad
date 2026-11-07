import SwiftUI

// The header toolbar model shared by `AppHeader`, `DetailHeader`, the glass
// buttons and `ToolbarGroup`. A header draws its items in one of four stages,
// the first that fits its half of the row, like an iPadOS toolbar that runs
// out of room. The buttons read the stage from the environment, so apps pass
// plain `GlassIconButton`s and `GlassCapsuleButton`s and get the right look.

/// How much room a header toolbar has, from the most to the least.
enum ToolbarStage: Int, Comparable {
    /// Every item as declared, text buttons with their titles.
    case full
    /// Text buttons that have a symbol show only the symbol.
    case compact
    /// Low priority items also move into the More menu.
    case overflow
    /// Every item but the prominent action sits in the More menu.
    case minimal

    static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    /// True when an item sits in the More menu at this stage instead of the bar.
    func movesToMenu(_ priority: ToolbarItemPriority, isProminent: Bool) -> Bool {
        guard !isProminent else { return false }
        switch self {
        case .full, .compact: return false
        case .overflow: return priority == .low
        case .minimal: return true
        }
    }
}

/// Where a glass button is drawn.
enum ToolbarPlacement: Equatable {
    /// Anywhere outside a header. Buttons keep their own sizes.
    case standalone
    /// In a header's bar, at a stage.
    case bar(ToolbarStage)
    /// In a header's More menu, at a stage.
    case menu(ToolbarStage)

    /// True in a header, in the bar or the More menu.
    var isToolbar: Bool {
        self != .standalone
    }

    /// True when text buttons show their titles. Menus always do.
    var showsTitles: Bool {
        if case .bar(let stage) = self { return stage == .full }
        return true
    }

    var isMenu: Bool {
        if case .menu = self { return true }
        return false
    }
}

/// Which header items give way first when a toolbar runs out of room.
public enum ToolbarItemPriority: Sendable {
    /// Stays in the bar until only the More menu, the prominent action and the
    /// close button fit. The default.
    case high
    /// Moves into the More menu first.
    case low
}

extension EnvironmentValues {
    @Entry var toolbarPlacement: ToolbarPlacement = .standalone
    @Entry var isInToolbarGroup = false
    @Entry var toolbarItemPriority: ToolbarItemPriority = .high
}

public extension EnvironmentValues {
    /// The app's own color, the tint of its icon. The one prominent action in
    /// its header is filled with it. The shell sets it from the app's
    /// `AppDescriptor.tint`. HomePad's accent color outside apps.
    @Entry var appAccent: Color = .accentColor
}

public extension View {
    /// Sets which header items move into the More menu first when the toolbar
    /// runs out of room. Put it on a `ToolbarGroup` to move the whole group.
    ///
    ///     GlassIconButton("photo.badge.plus", label: "Choose Photos") { pick() }
    ///         .toolbarItemPriority(.low)
    func toolbarItemPriority(_ priority: ToolbarItemPriority) -> some View {
        environment(\.toolbarItemPriority, priority)
    }

    /// Makes a view that is not one of the HomePadUI buttons, such as a
    /// `PhotosPicker` or `ShareLink` with a glass style, a header toolbar item:
    /// it shows in the bar, or in the More menu when the toolbar is short of room.
    ///
    ///     PhotosPicker(selection: $items) { Label("Choose Photos", systemImage: "photo.badge.plus") }
    ///         .buttonStyle(.glassIcon())
    ///         .headerItem()
    func headerItem() -> some View {
        modifier(ToolbarItemVisibility(isProminent: false))
    }

    /// Sets the app's own color (`\.appAccent`). The shell already sets the
    /// tint of the app's icon, so use it only for a surface that needs another
    /// color. The header's prominent action is filled with it.
    ///
    ///     AppScreen("Calendar") { ... }.appAccent(.red)
    func appAccent(_ color: Color) -> some View {
        environment(\.appAccent, color)
    }
}

/// Draws a header item in the bar or in the More menu, never in both.
struct ToolbarItemVisibility: ViewModifier {
    let isProminent: Bool
    @Environment(\.toolbarPlacement) private var placement
    @Environment(\.toolbarItemPriority) private var priority

    @ViewBuilder
    func body(content: Content) -> some View {
        switch placement {
        case .standalone:
            content
        case .bar(let stage):
            if !stage.movesToMenu(priority, isProminent: isProminent) { content }
        case .menu(let stage):
            if stage.movesToMenu(priority, isProminent: isProminent) { content }
        }
    }
}

/// Type and spacing every toolbar item shares.
enum ToolbarMetrics {
    /// The symbol in an icon item, about 20 points in a 48 point item.
    static let symbolFont = Font.system(size: 20, weight: .semibold)
    /// The title of a text item. Apple's bar text, a size up for the room.
    static let titleFont = Font.headline
    /// An icon item inside a `ToolbarGroup` is narrower than a lone circle, as on iPadOS.
    static let groupedIconWidth = Theme.Size.minTapTarget
    /// Longer titles are cut off, so a speaker name never fills the toolbar.
    static let maxTitleWidth: CGFloat = 260
    /// Headers stop growing at the largest curated text size (Huge).
    static let largestTypeSize = DynamicTypeSize.xxxLarge
}

/// Header geometry for screens that size their own content to the header,
/// such as a long album title that moves into the content when it does not fit.
public enum HeaderMetrics {
    /// The width each side of a header row gets: half of what is left beside
    /// the Now Playing zone.
    public static func sideWidth(rowWidth: CGFloat) -> CGFloat {
        HeaderSplit.app.sides(rowWidth: rowWidth).trailing
    }

    /// The room a title has in a header row this wide, after the back button when there is one.
    public static func titleRoom(rowWidth: CGFloat, hasBackButton: Bool) -> CGFloat {
        let back = hasBackButton ? Theme.Size.toolbarItem + Theme.Spacing.s : 0
        return max(0, sideWidth(rowWidth: rowWidth) - back)
    }
}

/// How a header row divides its width between the title side, an empty
/// center and the toolbar side.
struct HeaderSplit: Equatable {
    /// The empty width between the sides.
    let center: CGFloat
    /// The toolbar side's share of what the center leaves, at most half.
    let trailingShare: CGFloat
    /// The least width the toolbar side gets, while that is under half.
    let minimumTrailing: CGFloat
    /// True when the toolbar side also takes what a short title leaves.
    let toolbarTakesTitleRoom: Bool

    /// An app's header: halves around the Now Playing zone, where the pill shows.
    static let app = HeaderSplit(center: Theme.Size.nowPlayingZone, trailingShare: 0.5, minimumTrailing: 0,
                                 toolbarTakesTitleRoom: false)

    /// A sheet's header. The pill never covers a sheet, since UIKit presents
    /// sheets above the shell that draws it, so the sides are only
    /// `Theme.Spacing.l` apart. The toolbar takes what the title leaves, so
    /// "Add 3 to Groceries" keeps its words beside a short title. A long
    /// title keeps 60 percent, and the toolbar never gets less than the 160
    /// points Post and the close button take.
    static let sheet = HeaderSplit(center: Theme.Spacing.l, trailingShare: 0.4, minimumTrailing: 160,
                                   toolbarTakesTitleRoom: true)

    /// A sheet with no toolbar: the close button's width, and the rest for the title.
    static let sheetCloseOnly = HeaderSplit(center: Theme.Spacing.l, trailingShare: 0, minimumTrailing: Theme.Size.toolbarItem,
                                            toolbarTakesTitleRoom: false)

    /// The widths of the leading and trailing sides of a row this wide.
    /// - Parameter titleWidth: What the title side needs at full size, when
    ///   known. It never depends on the sides, so the split settles in one update.
    func sides(rowWidth: CGFloat, titleWidth: CGFloat? = nil) -> (leading: CGFloat, trailing: CGFloat) {
        let room = max(0, rowWidth - center)
        var trailing = min(room / 2, max(room * trailingShare, minimumTrailing))
        if toolbarTakesTitleRoom, let titleWidth {
            trailing = max(trailing, room - titleWidth)
        }
        return (room - trailing, trailing)
    }
}
