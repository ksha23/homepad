import SwiftUI

/// A grid where each tile spans one or two columns, packed in order like
/// Apple Home's small and wide accessory tiles. Set a tile's span with
/// `.tileSpan(2)`.
///
///     TileGridLayout(minimumColumnWidth: 160, rowHeight: 140, spacing: Theme.Spacing.m) {
///         ForEach(accessories) { AccessoryTile($0).tileSpan($0.isWide ? 2 : 1) }
///     }
public struct TileGridLayout: Layout {
    private let minimumColumnWidth: CGFloat
    private let rowHeight: CGFloat
    private let spacing: CGFloat

    /// - Parameters:
    ///   - minimumColumnWidth: Columns are at least this wide. At least two columns always fit.
    ///   - rowHeight: Height of every row.
    ///   - spacing: Gap between tiles, across and down.
    public init(minimumColumnWidth: CGFloat, rowHeight: CGFloat, spacing: CGFloat = Theme.Spacing.m) {
        self.minimumColumnWidth = minimumColumnWidth
        self.rowHeight = rowHeight
        self.spacing = spacing
    }

    public func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? minimumColumnWidth * 4
        let frames = frames(width: width, subviews: subviews)
        return CGSize(width: width, height: frames.map(\.maxY).max() ?? 0)
    }

    public func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for (subview, frame) in zip(subviews, frames(width: bounds.width, subviews: subviews)) {
            subview.place(at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY),
                          proposal: ProposedViewSize(frame.size))
        }
    }

    /// Number of columns that fit the width.
    public func columns(for width: CGFloat) -> Int {
        max(2, Int((width + spacing) / (minimumColumnWidth + spacing)))
    }

    private func frames(width: CGFloat, subviews: Subviews) -> [CGRect] {
        let columns = columns(for: width)
        let columnWidth = (width - spacing * CGFloat(columns - 1)) / CGFloat(columns)
        var column = 0
        var row = 0
        return subviews.map { subview in
            let span = min(max(subview[TileSpanKey.self], 1), columns)
            if column + span > columns {
                column = 0
                row += 1
            }
            let frame = CGRect(
                x: CGFloat(column) * (columnWidth + spacing),
                y: CGFloat(row) * (rowHeight + spacing),
                width: columnWidth * CGFloat(span) + spacing * CGFloat(span - 1),
                height: rowHeight
            )
            column += span
            return frame
        }
    }
}

private struct TileSpanKey: LayoutValueKey {
    static let defaultValue = 1
}

public extension View {
    /// How many columns this tile covers in a `TileGridLayout`.
    func tileSpan(_ span: Int) -> some View {
        layoutValue(key: TileSpanKey.self, value: span)
    }
}
