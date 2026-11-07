import CoreGraphics

/// The cells of a grid `GridPacker` fills, and where a placement sits in it.
/// The Home Screen and Control Center draw their grids with it.
struct GridGeometry: Equatable {
    var cellSize: CGSize
    /// Gap between cells, across and down.
    var spacing: CGFloat

    /// The frame of a placement, from the grid's top leading corner.
    func frame(for placement: GridPlacement) -> CGRect {
        CGRect(
            x: CGFloat(placement.column) * (cellSize.width + spacing),
            y: CGFloat(placement.row) * (cellSize.height + spacing),
            width: width(columns: placement.span.columns),
            height: height(rows: placement.span.rows)
        )
    }

    /// The width of this many columns and the gaps between them.
    func width(columns: Int) -> CGFloat {
        CGFloat(columns) * cellSize.width + CGFloat(max(columns - 1, 0)) * spacing
    }

    /// The height of this many rows and the gaps between them.
    func height(rows: Int) -> CGFloat {
        CGFloat(rows) * cellSize.height + CGFloat(max(rows - 1, 0)) * spacing
    }
}
