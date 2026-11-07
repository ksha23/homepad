import CoreGraphics
import HomePadCore
import HomePadUI
import SwiftUI

/// The part of a face its own content needs, mainly the clock and the date,
/// for a face whose content stays put (`FaceWidgetSupport.region`). The grid
/// blocks every cell it covers (`FaceGrid.blocked`), so no widget can be
/// placed over the time.
///
/// Widgets show at every distance, so a face whose content changes between
/// across the room and up close declares the union of both: the time never
/// slides under a widget as someone walks up or away.
struct FaceContentRegion: Sendable {
    private let make: @Sendable (FaceConfiguration, CGSize, EdgeInsets) -> [CGRect]

    /// - Parameter make: The rects the content needs, in the face's coordinates,
    ///   for a face saved as `configuration`, of this size, with these face insets.
    init(_ make: @escaping @Sendable (_ configuration: FaceConfiguration, _ size: CGSize, _ insets: EdgeInsets) -> [CGRect]) {
        self.make = make
    }

    /// The rects the content needs.
    func rects(configuration: FaceConfiguration, size: CGSize, insets: EdgeInsets) -> [CGRect] {
        make(configuration, size, insets)
    }

    /// Nothing: art faces (Flow) take widgets anywhere.
    static let none = FaceContentRegion { _, _, _ in [] }

    /// A rect centered on the face, its sides shares of the face's shorter
    /// side, such as a dial and its numerals.
    static func centered(width: CGFloat, height: CGFloat) -> FaceContentRegion {
        FaceContentRegion { _, size, _ in
            let side = min(size.width, size.height)
            let rect = CGSize(width: side * width, height: side * height)
            return [CGRect(x: (size.width - rect.width) / 2, y: (size.height - rect.height) / 2,
                           width: rect.width, height: rect.height)]
        }
    }

    /// The rects of several regions together.
    static func union(_ regions: [FaceContentRegion]) -> FaceContentRegion {
        FaceContentRegion { configuration, size, insets in
            regions.flatMap { $0.rects(configuration: configuration, size: size, insets: insets) }
        }
    }

    /// Rects given as shares of the content area inside the face insets, one
    /// list for each orientation. `CGRect(x: 0, y: 0, width: 1, height: 0.5)`
    /// is the top half of the content.
    static func content(landscape: [CGRect], portrait: [CGRect]) -> FaceContentRegion {
        FaceContentRegion { _, size, insets in
            let content = CGRect(x: insets.leading, y: insets.top,
                                 width: size.width - insets.leading - insets.trailing,
                                 height: size.height - insets.top - insets.bottom)
            let shares = FaceGrid.Orientation(size) == .landscape ? landscape : portrait
            return shares.map { share in
                CGRect(x: content.minX + share.minX * content.width, y: content.minY + share.minY * content.height,
                       width: share.width * content.width, height: share.height * content.height)
            }
        }
    }
}

/// A part of the grid set aside for widgets, along one side for each
/// orientation. A face whose content fills the screen
/// (`FaceWidgetSupport.widgetArea`) keeps out of it while it has widgets,
/// and takes the whole screen again when it has none.
struct FaceWidgetArea: Equatable, Sendable {
    /// Where the area lies on a grid.
    enum Side: Equatable, Sendable {
        /// This many columns on the trailing side.
        case trailing(columns: Int)
        /// This many rows along the bottom.
        case bottom(rows: Int)
    }

    var landscape: Side = .trailing(columns: 2)
    var portrait: Side = .bottom(rows: 2)

    func side(for orientation: FaceGrid.Orientation) -> Side {
        orientation == .landscape ? landscape : portrait
    }

    /// The face's content area beside the widgets: the cells not set aside,
    /// as a rect in the face's coordinates.
    func contentFrame(on grid: FaceGrid) -> CGRect {
        let area = switch side(for: grid.orientation) {
        case .trailing(let columns):
            FaceGridArea(column: 0, row: 0, columns: grid.columns - min(max(columns, 0), grid.columns - 1), rows: grid.rows)
        case .bottom(let rows):
            FaceGridArea(column: 0, row: 0, columns: grid.columns, rows: grid.rows - min(max(rows, 0), grid.rows - 1))
        }
        return grid.frame(for: area)
    }

    /// Where widgets with no cell of their own go: down the column, or along the bottom.
    func fill(for orientation: FaceGrid.Orientation) -> FaceGridFill {
        if case .trailing = side(for: orientation) { return .trailingColumns }
        return .bottomRows
    }
}

/// How a face takes widgets on its grid: where its own content goes, and
/// where widgets without a cell of their own go first.
///
/// A face's content stays out of the widgets' way in one of two ways:
/// - `widgetArea`: content that fills the screen (Modular, Weather, Calendar,
///   Cameras) moves out of a set-aside area while the face has widgets
///   (`widgetRoom`), and widgets go anywhere in that area.
/// - `region`: content that stays put (a dial, the Photos time) blocks the
///   cells it covers, and widgets go anywhere else.
struct FaceWidgetSupport: Sendable {
    /// False for a face that shows other faces (Smart Rotation), whose widgets
    /// are those of the face it shows.
    var allowsWidgets = true
    /// The area set aside for widgets, for a face whose content fills the screen.
    var widgetArea: FaceWidgetArea?
    /// Where content that stays put is, for a face without a widget area.
    var region: FaceContentRegion = .none
    var landscapeFill: FaceGridFill = .bottomRows
    var portraitFill: FaceGridFill = .bottomRows
    /// The size the face's old widget slots become (`FaceWidgetMigration`).
    var legacySize: WidgetSize = .small
    /// The face is red at every hour (Night), so its widgets are too.
    var isAlwaysNight = false

    /// Widgets anywhere, filling from the bottom row.
    static let anywhere = FaceWidgetSupport()
    /// No widgets of its own.
    static let unsupported = FaceWidgetSupport(allowsWidgets: false)

    /// A face whose content fills the screen and moves aside for widgets:
    /// beside two columns in landscape and over two rows in portrait, unless
    /// `area` says otherwise.
    static func besideWidgets(_ area: FaceWidgetArea = FaceWidgetArea(), legacySize: WidgetSize = .small,
                              isAlwaysNight: Bool = false) -> FaceWidgetSupport {
        FaceWidgetSupport(widgetArea: area, landscapeFill: area.fill(for: .landscape),
                          portraitFill: area.fill(for: .portrait), legacySize: legacySize, isAlwaysNight: isAlwaysNight)
    }

    /// A face whose content stays in `region`, with widgets around it.
    static func around(_ region: FaceContentRegion, landscapeFill: FaceGridFill = .bottomRows,
                       portraitFill: FaceGridFill = .bottomRows) -> FaceWidgetSupport {
        FaceWidgetSupport(region: region, landscapeFill: landscapeFill, portraitFill: portraitFill)
    }

    func fill(for orientation: FaceGrid.Orientation) -> FaceGridFill {
        orientation == .landscape ? landscapeFill : portraitFill
    }

    /// The face's grid, with the cells its content needs blocked, and those
    /// under the Now Playing pill (`nowPlayingZone`) and the profile button
    /// (`profileZone`). The mini widget sits in the top margin, above the grid.
    /// - Parameter insets: The face insets without the pill's room (`\.faceNowPlayingRoom`).
    func grid(configuration: FaceConfiguration, size: CGSize, insets: EdgeInsets) -> FaceGrid {
        let shell = [Self.nowPlayingZone(size: size, insets: insets), Self.profileZone(size: size, insets: insets)]
        if let widgetArea {
            let open = FaceGrid(size: size, insets: insets)
            return FaceGrid(size: size, insets: insets, protecting: [widgetArea.contentFrame(on: open)] + shell)
        }
        return FaceGrid(size: size, insets: insets,
                        protecting: region.rects(configuration: configuration, size: size, insets: insets) + shell)
    }

    /// Where the Now Playing pill shows at the top center of a face while
    /// music plays, down to the room the face makes for it. Widgets keep
    /// clear of it whether or not music plays, so none moves when it starts.
    static func nowPlayingZone(size: CGSize, insets: EdgeInsets) -> CGRect {
        let width = Theme.Size.faceNowPlayingWidth
        return CGRect(x: (size.width - width) / 2, y: 0, width: width, height: insets.top + Theme.Size.faceNowPlayingRoom)
    }

    /// The face's top trailing corner, down to the bottom of the profile
    /// button the shell draws there (`Theme.Size.profileButtonInset` from the
    /// screen's top and trailing edges) and a gap. Widgets keep clear of it
    /// whether or not anyone is set up, so none moves when someone is added.
    /// - Parameter insets: The face insets, which include the burn-in overscan on the wall.
    static func profileZone(size: CGSize, insets: EdgeInsets) -> CGRect {
        let overscan = max(insets.trailing - Theme.Spacing.screenContent.trailing, 0)
        let reach = overscan + Theme.Size.profileButtonInset + Theme.Size.profileButton + FaceGrid.gap
        return CGRect(x: size.width - reach, y: 0, width: reach, height: reach)
    }

    /// How tall a face's mini widget is: room for one line of symbols and
    /// counts with `Theme.Spacing.s` around it, and short enough to fit the
    /// face's top margin (`Theme.Spacing.screenContent.top`) with room above.
    static let miniWidgetHeight: CGFloat = 36

    /// Where a face's mini widget may be: in the face's top margin, ending
    /// where the face's content starts (`insets.top`), from the shell's leading
    /// margin across to a gap before the Now Playing pill's zone. Nothing of
    /// the face is laid out there, so no face moves for it. The widget hugs its
    /// content inside it and shows less before it would grow past it.
    /// - Parameter insets: The face insets without the pill's room, which include the burn-in overscan on the wall.
    static func miniWidgetFrame(size: CGSize, insets: EdgeInsets) -> CGRect {
        let overscanLeading = max(insets.leading - Theme.Spacing.screenContent.leading, 0)
        let x = overscanLeading + Theme.Spacing.screenMargin.leading
        let pills = nowPlayingZone(size: size, insets: insets)
        return CGRect(x: x, y: insets.top - miniWidgetHeight, width: max(pills.minX - FaceGrid.gap - x, 0),
                      height: miniWidgetHeight)
    }

    /// The room the face's content leaves for its widget area, from the
    /// face's own edges: on the trailing side or the bottom, up to a gap
    /// before the widgets. Zero without widgets, or without a widget area.
    /// Faces laid out by `\.faceInsets` get it added to them, and faces that
    /// center on the whole face read it in `\.faceKeepClear`.
    func widgetRoom(size: CGSize, insets: EdgeInsets, hasWidgets: Bool) -> EdgeInsets {
        guard let widgetArea, hasWidgets else { return EdgeInsets() }
        let content = widgetArea.contentFrame(on: FaceGrid(size: size, insets: insets))
        return EdgeInsets(top: 0, leading: 0,
                          bottom: max(size.height - insets.bottom - content.maxY, 0),
                          trailing: max(size.width - insets.trailing - content.maxX, 0))
    }
}
