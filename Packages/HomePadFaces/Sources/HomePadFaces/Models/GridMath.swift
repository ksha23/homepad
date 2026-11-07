import CoreGraphics
import Foundation

/// Picks grid dimensions for a number of equal cells, used by the camera
/// wall and the world clock so both look balanced in landscape and portrait.
enum GridMath {
    struct Dimensions: Equatable {
        var columns: Int
        var rows: Int
    }

    /// The grid whose cells come closest to `cellAspect` (width over height)
    /// in a container, with few empty cells.
    static func dimensions(count: Int, in size: CGSize, cellAspect: CGFloat) -> Dimensions {
        guard count > 1, size.width > 0, size.height > 0 else { return Dimensions(columns: 1, rows: 1) }
        var best = Dimensions(columns: count, rows: 1)
        var bestScore = Double.infinity
        for columns in 1...count {
            let rows = Int((Double(count) / Double(columns)).rounded(.up))
            let aspect = (size.width / CGFloat(columns)) / (size.height / CGFloat(rows))
            let empty = columns * rows - count
            let score = abs(log(Double(aspect / cellAspect))) + Double(empty) * 0.35
            if score < bestScore {
                bestScore = score
                best = Dimensions(columns: columns, rows: rows)
            }
        }
        return best
    }
}
