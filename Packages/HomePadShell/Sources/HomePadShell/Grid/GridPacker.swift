/// Where one item landed in a grid.
struct GridPlacement: Equatable, Sendable {
    /// Index of the item in the input list.
    var index: Int
    var column: Int
    var row: Int
    var span: GridSpan
}

/// Packs items of different spans into a fixed grid, first fit in reading
/// order, the way iPadOS fills a Home Screen page. Items that no longer fit
/// start a new page. Used by the Home Screen and by Control Center.
enum GridPacker {
    static func paginate(_ spans: [GridSpan], columns: Int, rows: Int) -> [[GridPlacement]] {
        let columns = max(columns, 1)
        let rows = max(rows, 1)
        var pages: [[GridPlacement]] = []
        var current: [GridPlacement] = []
        var occupied = emptyGrid(columns: columns, rows: rows)

        for (index, raw) in spans.enumerated() {
            let span = GridSpan(columns: min(raw.columns, columns), rows: min(raw.rows, rows))
            if firstFit(span, in: occupied) == nil {
                pages.append(current)
                current = []
                occupied = emptyGrid(columns: columns, rows: rows)
            }
            guard let spot = firstFit(span, in: occupied) else { continue }
            mark(span, at: spot, in: &occupied)
            current.append(GridPlacement(index: index, column: spot.column, row: spot.row, span: span))
        }
        if !current.isEmpty || pages.isEmpty { pages.append(current) }
        return pages
    }

    /// Packs into one unbounded-height grid (Control Center scrolls instead of paging).
    static func pack(_ spans: [GridSpan], columns: Int) -> [GridPlacement] {
        let rows = spans.reduce(0) { $0 + $1.rows }
        return paginate(spans, columns: columns, rows: max(rows, 1)).first ?? []
    }

    /// How many rows the placements fill.
    static func rowCount(_ placements: [GridPlacement]) -> Int {
        placements.map { $0.row + $0.span.rows }.max() ?? 0
    }

    private static func emptyGrid(columns: Int, rows: Int) -> [[Bool]] {
        Array(repeating: Array(repeating: false, count: columns), count: rows)
    }

    private static func firstFit(_ span: GridSpan, in grid: [[Bool]]) -> (column: Int, row: Int)? {
        let rows = grid.count
        let columns = grid.first?.count ?? 0
        guard span.rows <= rows, span.columns <= columns else { return nil }
        for row in 0...(rows - span.rows) {
            for column in 0...(columns - span.columns) where isFree(span, column: column, row: row, in: grid) {
                return (column, row)
            }
        }
        return nil
    }

    private static func isFree(_ span: GridSpan, column: Int, row: Int, in grid: [[Bool]]) -> Bool {
        for r in row..<(row + span.rows) {
            for c in column..<(column + span.columns) where grid[r][c] {
                return false
            }
        }
        return true
    }

    private static func mark(_ span: GridSpan, at spot: (column: Int, row: Int), in grid: inout [[Bool]]) {
        for r in spot.row..<(spot.row + span.rows) {
            for c in spot.column..<(spot.column + span.columns) {
                grid[r][c] = true
            }
        }
    }
}
