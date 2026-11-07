/// Where a face puts widgets that have no cell of their own yet: one just
/// added, those carried over from the other orientation, or those from the
/// face's old widget slots.
///
/// Such widgets go together, in reading order, into the narrowest band along
/// the fill's edge that holds them all (`FaceWidgetBoard`). So they keep
/// their order, and a few widgets sit against the edge rather than above an
/// empty row.
enum FaceGridFill: String, Sendable, CaseIterable {
    /// The whole grid from the top, as you read.
    case readingOrder
    /// Along the bottom: the bottom row first, then the two bottom rows, and
    /// so on, like the Photos face's row under the time.
    case bottomRows
    /// Along the trailing side: the last column first, then the last two, and
    /// so on, like the iPad's widget column beside Modular's information.
    case trailingColumns

    /// Part of the grid, from a column and a row to its trailing and bottom edges.
    struct Band: Equatable, Sendable {
        var fromColumn = 0
        var fromRow = 0

        func contains(_ area: FaceGridArea) -> Bool {
            area.column >= fromColumn && area.row >= fromRow
        }
    }

    /// The bands this fill tries, narrowest first. The last is the whole grid.
    func bands(columns: Int, rows: Int) -> [Band] {
        switch self {
        case .readingOrder: [Band()]
        case .bottomRows: (0..<max(rows, 1)).reversed().map { Band(fromRow: $0) }
        case .trailingColumns: (0..<max(columns, 1)).reversed().map { Band(fromColumn: $0) }
        }
    }
}
