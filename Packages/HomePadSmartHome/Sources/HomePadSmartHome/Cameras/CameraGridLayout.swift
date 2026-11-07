import CoreGraphics
import SwiftUI

/// Sizes the camera grid: every tile has a camera's 16:9 shape, with the column
/// count that makes the tiles largest in the space. Tiles never stretch to fill
/// leftover height, which would turn a wide picture into a tall one. When two
/// layouts are about as large, the one that follows the screen wins: more
/// columns in landscape, fewer in portrait.
enum CameraGridLayout {
    /// Most security cameras and HomeKit streams are 16:9.
    static let aspectRatio: CGFloat = 16.0 / 9.0

    static func best(count: Int, in size: CGSize, spacing: CGFloat) -> (columns: Int, tile: CGSize) {
        guard count > 0 else { return (1, .zero) }
        let candidates = (1...count).map { columns in
            let rows = (count + columns - 1) / columns
            let cellWidth = (size.width - spacing * CGFloat(columns - 1)) / CGFloat(columns)
            let cellHeight = (size.height - spacing * CGFloat(rows - 1)) / CGFloat(rows)
            let width = max(min(cellWidth, cellHeight * aspectRatio), 0)
            return (columns: columns, tile: CGSize(width: width, height: width / aspectRatio))
        }
        let largest = candidates.map(\.tile.width).max() ?? 0
        let close = candidates.filter { $0.tile.width >= largest * 0.95 }
        let pick = size.width >= size.height ? close.max { $0.columns < $1.columns } : close.min { $0.columns < $1.columns }
        return pick ?? (1, .zero)
    }
}

extension EnvironmentValues {
    /// How camera pictures meet their frame: cropped to fill (grid tiles) or
    /// fitted whole (full screen). Set by `CameraFeedView` from its purpose.
    @Entry var cameraContentMode: ContentMode = .fill
}
