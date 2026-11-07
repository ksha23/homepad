import CoreGraphics
import HomePadCore

/// One cell of a face's widget grid, counted from the top leading corner.
struct FaceGridCell: Codable, Hashable, Sendable {
    var column: Int
    var row: Int

    init(column: Int, row: Int) {
        self.column = column
        self.row = row
    }
}

/// A rectangle of cells: where a widget sits on a face's grid.
struct FaceGridArea: Hashable, Sendable {
    var column: Int
    var row: Int
    var columns: Int
    var rows: Int

    init(column: Int, row: Int, columns: Int, rows: Int) {
        self.column = column
        self.row = row
        self.columns = max(columns, 1)
        self.rows = max(rows, 1)
    }

    /// The cells a widget of `size` covers with its top leading corner in `origin`.
    init(origin: FaceGridCell, size: WidgetSize) {
        self.init(column: origin.column, row: origin.row, columns: size.columns, rows: size.rows)
    }

    /// The top leading cell.
    var origin: FaceGridCell { FaceGridCell(column: column, row: row) }

    /// One past the trailing column.
    var endColumn: Int { column + columns }
    /// One past the bottom row.
    var endRow: Int { row + rows }

    /// Every cell, row by row.
    var cells: [FaceGridCell] {
        (row..<endRow).flatMap { row in (column..<endColumn).map { FaceGridCell(column: $0, row: row) } }
    }

    func contains(_ cell: FaceGridCell) -> Bool {
        (column..<endColumn).contains(cell.column) && (row..<endRow).contains(cell.row)
    }

    func intersects(_ other: FaceGridArea) -> Bool {
        column < other.endColumn && other.column < endColumn && row < other.endRow && other.row < endRow
    }

    /// The same area with its top leading corner in `origin`.
    func moved(to origin: FaceGridCell) -> FaceGridArea {
        FaceGridArea(column: origin.column, row: origin.row, columns: columns, rows: rows)
    }
}

extension WidgetSize {
    /// Sizes from largest to smallest, the order a widget steps down in when it has no room.
    static let largestFirst: [WidgetSize] = [.tall, .large, .medium, .small]
}
