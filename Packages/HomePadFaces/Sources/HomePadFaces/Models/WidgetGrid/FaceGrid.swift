import CoreGraphics
import HomePadCore
import HomePadUI
import SwiftUI

/// The grid widgets snap to on a face. It fills the face's content area
/// inside the face insets: six columns by four rows in landscape and four by
/// six in portrait, like the Home Screen's six and four columns.
///
/// The counts are the same on every iPad, so a face synced through iCloud
/// keeps its layout on an 11 and a 13 inch iPad. Only the cells grow: they
/// come out nearly square, about 160 points on an 11-inch iPad and 190 to
/// 210 on a 13-inch, the size of a small widget on the Home Screen.
///
/// Cells the face's own content needs, mainly its clock and date, are
/// blocked (`FaceContentRegion`), and no widget may cover them.
struct FaceGrid: Equatable, Sendable {
    /// Landscape and portrait have their own grids and their own layouts.
    enum Orientation: String, Codable, CaseIterable, Sendable {
        case landscape
        case portrait

        /// Landscape when the face is at least as wide as it is tall.
        init(_ size: CGSize) {
            self = size.width >= size.height ? .landscape : .portrait
        }

        var other: Orientation { self == .landscape ? .portrait : .landscape }
        var columns: Int { self == .landscape ? 6 : 4 }
        var rows: Int { self == .landscape ? 4 : 6 }

        var title: String { self == .landscape ? "Landscape" : "Portrait" }
        var systemImage: String { self == .landscape ? "rectangle" : "rectangle.portrait" }
    }

    let orientation: Orientation
    /// The face's content area, inside the face insets, that the cells fill.
    let content: CGRect
    /// The gap between cells, across and down.
    let gap: CGFloat
    let cellSize: CGSize
    /// Cells the face's own content needs.
    let blocked: Set<FaceGridCell>

    var columns: Int { orientation.columns }
    var rows: Int { orientation.rows }

    /// Between cells: the Home Screen's grid gutter.
    static let gap = Theme.Spacing.l
    /// How far a protected rect may reach into a cell before the cell is
    /// blocked, as a share of the cell's shorter side. A clock's bounding box
    /// that only grazes a cell, or the few points of burn-in overscan, leave it open.
    static let blockingTolerance: CGFloat = 0.06

    /// - Parameters:
    ///   - size: The face's size.
    ///   - insets: The face insets (`\.faceInsets`), which include the burn-in overscan on the wall.
    ///   - rects: Where the face's own content is, in the face's coordinates.
    init(size: CGSize, insets: EdgeInsets, protecting rects: [CGRect] = []) {
        let orientation = Orientation(size)
        let content = CGRect(
            x: insets.leading, y: insets.top,
            width: max(size.width - insets.leading - insets.trailing, 1),
            height: max(size.height - insets.top - insets.bottom, 1)
        )
        let gap = Self.gap
        let cell = CGSize(
            width: max((content.width - gap * CGFloat(orientation.columns - 1)) / CGFloat(orientation.columns), 1),
            height: max((content.height - gap * CGFloat(orientation.rows - 1)) / CGFloat(orientation.rows), 1)
        )
        self.orientation = orientation
        self.content = content
        self.gap = gap
        cellSize = cell

        let tolerance = min(cell.width, cell.height) * Self.blockingTolerance
        var blocked = Set<FaceGridCell>()
        for row in 0..<orientation.rows {
            for column in 0..<orientation.columns {
                let frame = CGRect(
                    x: content.minX + CGFloat(column) * (cell.width + gap),
                    y: content.minY + CGFloat(row) * (cell.height + gap),
                    width: cell.width, height: cell.height
                )
                let isCovered = rects.contains { rect in
                    let overlap = frame.intersection(rect)
                    return !overlap.isNull && overlap.width > tolerance && overlap.height > tolerance
                }
                if isCovered { blocked.insert(FaceGridCell(column: column, row: row)) }
            }
        }
        self.blocked = blocked
    }

    // MARK: Geometry

    /// An area's frame in the face's coordinates.
    func frame(for area: FaceGridArea) -> CGRect {
        CGRect(
            x: content.minX + CGFloat(area.column) * (cellSize.width + gap),
            y: content.minY + CGFloat(area.row) * (cellSize.height + gap),
            width: CGFloat(area.columns) * cellSize.width + CGFloat(area.columns - 1) * gap,
            height: CGFloat(area.rows) * cellSize.height + CGFloat(area.rows - 1) * gap
        )
    }

    func frame(for cell: FaceGridCell) -> CGRect {
        frame(for: FaceGridArea(column: cell.column, row: cell.row, columns: 1, rows: 1))
    }

    /// The size a widget of `size` is drawn at on this grid.
    func tileSize(_ size: WidgetSize) -> CGSize {
        frame(for: FaceGridArea(column: 0, row: 0, columns: size.columns, rows: size.rows)).size
    }

    // MARK: Room

    /// True when the area lies inside the grid.
    func contains(_ area: FaceGridArea) -> Bool {
        area.column >= 0 && area.row >= 0 && area.endColumn <= columns && area.endRow <= rows
    }

    /// True when the area lies inside the grid and covers none of the face's own content.
    func isOpen(_ area: FaceGridArea) -> Bool {
        contains(area) && !area.cells.contains { blocked.contains($0) }
    }

    /// Every area a widget of `size` could take, ignoring other widgets, top row first.
    func openAreas(for size: WidgetSize) -> [FaceGridArea] {
        guard size.columns <= columns, size.rows <= rows else { return [] }
        return (0...(rows - size.rows)).flatMap { row in
            (0...(columns - size.columns)).map { column in
                FaceGridArea(column: column, row: row, columns: size.columns, rows: size.rows)
            }
        }
        .filter(isOpen)
    }

    /// Cells no content blocks, row by row.
    var openCells: [FaceGridCell] {
        (0..<rows).flatMap { row in (0..<columns).map { FaceGridCell(column: $0, row: row) } }
            .filter { !blocked.contains($0) }
    }

    /// True when a widget of `size` fits somewhere with no other widgets on the face.
    func hasRoom(for size: WidgetSize) -> Bool {
        !openAreas(for: size).isEmpty
    }
}
