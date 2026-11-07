import Foundation

/// Where one tile lands on the Home face grid.
struct TilePlacement: Equatable {
    var index: Int
    var column: Int
    var row: Int
    var width: Int
}

/// Packs tiles of width 1 or 2 into a fixed grid, left to right and top to
/// bottom, the way HomeView fills its Home Modular face. A tile that does not
/// fit in the remaining space is skipped, and packing stops when the grid is full.
enum TileGridPacker {
    static func pack(widths: [Int], columns: Int, rows: Int) -> [TilePlacement] {
        guard columns > 0, rows > 0 else { return [] }
        var taken = Array(repeating: Array(repeating: false, count: columns), count: rows)
        var placements: [TilePlacement] = []
        for (index, rawWidth) in widths.enumerated() {
            let width = min(max(rawWidth, 1), columns)
            guard let spot = firstFree(width: width, in: taken) else { continue }
            for column in spot.column..<(spot.column + width) { taken[spot.row][column] = true }
            placements.append(TilePlacement(index: index, column: spot.column, row: spot.row, width: width))
            if taken.allSatisfy({ $0.allSatisfy { $0 } }) { break }
        }
        return placements
    }

    private static func firstFree(width: Int, in taken: [[Bool]]) -> (row: Int, column: Int)? {
        for row in taken.indices {
            let cells = taken[row]
            for column in 0...(cells.count - width) where cells[column..<(column + width)].allSatisfy({ !$0 }) {
                return (row, column)
            }
        }
        return nil
    }
}
