import CoreGraphics
import HomePadUI

/// Grid geometry for a Home Screen page: few, large cells so icons read from
/// across the room. Six columns in landscape and four in portrait, one fewer
/// at the largest text sizes. Rows stretch to fill the page height, so no
/// iPad size is left with an empty band at the bottom.
struct HomeGridMetrics: Equatable {
    var columns: Int
    var rows: Int
    var cellSize: CGSize
    var spacing: CGFloat
    var iconSize: CGFloat
    /// Room under a widget for its name.
    var widgetLabelHeight: CGFloat = 30

    init(size: CGSize, prefersLargerCells: Bool) {
        let landscape = size.width > size.height
        columns = (landscape ? 6 : 4) - (prefersLargerCells ? 1 : 0)
        spacing = Theme.Spacing.l
        let width = max((size.width - spacing * CGFloat(columns - 1)) / CGFloat(columns), 60)
        // As many rows as fit at the natural cell shape, then the cells grow
        // (by less than a row's worth) to use the leftover height.
        let naturalHeight = width * 0.92
        rows = max(1, Int((size.height + spacing) / (naturalHeight + spacing)))
        let filledHeight = (size.height - spacing * CGFloat(rows - 1)) / CGFloat(rows)
        cellSize = CGSize(width: width, height: max(naturalHeight, filledHeight))
        iconSize = (min(width, naturalHeight) * 0.64).rounded()
    }

    /// The frame of a placement inside the page.
    func frame(for placement: GridPlacement) -> CGRect {
        GridGeometry(cellSize: cellSize, spacing: spacing).frame(for: placement)
    }
}
