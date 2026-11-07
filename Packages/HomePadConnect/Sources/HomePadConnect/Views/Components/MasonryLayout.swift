import SwiftUI

/// Columns of one width, with each item placed under the shortest column so
/// far, like sticky notes on a board or a wall of photos. Items keep their
/// own height, so a short note stays small next to a long one, and the first
/// items run left to right across the top.
///
/// The width offered decides the columns: as many as bring them closest to
/// `idealColumnWidth`, never narrower than four fifths of it, and at least one.
/// `minimumHeightRatio` keeps the shortest items from turning into strips, so
/// a one-line note still has a note's shape.
///
///     MasonryLayout(idealColumnWidth: 240, spacing: Theme.Spacing.m, minimumHeightRatio: 0.5) {
///         ForEach(notes) { StickyNoteCard(note: $0) }
///     }
///
/// Candidate for HomePadUI.
struct MasonryLayout: Layout {
    var idealColumnWidth: CGFloat
    var spacing: CGFloat
    /// Items are at least this fraction of the column width tall.
    var minimumHeightRatio: CGFloat = 0

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let columns = MasonryColumns(width: proposal.width, ideal: idealColumnWidth, spacing: spacing)
        let packing = MasonryPacking(heights: heights(of: subviews, width: columns.width),
                                     columns: columns.count, spacing: spacing)
        return CGSize(width: proposal.width ?? columns.totalWidth(spacing: spacing), height: packing.height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let columns = MasonryColumns(width: bounds.width, ideal: idealColumnWidth, spacing: spacing)
        let heights = heights(of: subviews, width: columns.width)
        let packing = MasonryPacking(heights: heights, columns: columns.count, spacing: spacing)
        for (index, slot) in packing.slots.enumerated() {
            let x = bounds.minX + CGFloat(slot.column) * (columns.width + spacing)
            subviews[index].place(at: CGPoint(x: x, y: bounds.minY + slot.y),
                                  proposal: ProposedViewSize(width: columns.width, height: heights[index]))
        }
    }

    /// Each item's height at the column width, at least the minimum.
    private func heights(of subviews: Subviews, width: CGFloat) -> [CGFloat] {
        subviews.map { max($0.sizeThatFits(ProposedViewSize(width: width, height: nil)).height, width * minimumHeightRatio) }
    }
}

/// How many columns a width holds and how wide each is.
struct MasonryColumns: Equatable {
    let count: Int
    let width: CGFloat

    /// - Parameters:
    ///   - available: The width to fill. Without one there is a single column of the ideal width.
    ///   - ideal: The column width to come closest to.
    ///   - spacing: The gap between columns.
    init(width available: CGFloat?, ideal: CGFloat, spacing: CGFloat) {
        guard let available, available.isFinite, available > 0, ideal > 0 else {
            count = 1
            width = max(ideal, 0)
            return
        }
        var count = max(Int(((available + spacing) / (ideal + spacing)).rounded()), 1)
        // Rounding up can squeeze columns. Below four fifths of the ideal, use one fewer.
        while count > 1, Self.width(of: count, in: available, spacing: spacing) < ideal * 0.8 {
            count -= 1
        }
        self.count = count
        width = Self.width(of: count, in: available, spacing: spacing)
    }

    /// The width of all columns and the gaps between them.
    func totalWidth(spacing: CGFloat) -> CGFloat {
        width * CGFloat(count) + spacing * CGFloat(count - 1)
    }

    private static func width(of count: Int, in available: CGFloat, spacing: CGFloat) -> CGFloat {
        max((available - spacing * CGFloat(count - 1)) / CGFloat(count), 0)
    }
}

/// Where each item goes: in the shortest column so far, the leftmost one on a tie.
struct MasonryPacking: Equatable {
    struct Slot: Equatable {
        let column: Int
        let y: CGFloat
    }

    /// One slot per item, in order.
    let slots: [Slot]
    /// From the top of the first item to the bottom of the tallest column.
    let height: CGFloat

    init(heights: [CGFloat], columns: Int, spacing: CGFloat) {
        var bottoms = Array(repeating: CGFloat(0), count: max(columns, 1))
        var slots: [Slot] = []
        for height in heights {
            // `min(by:)` keeps the first of equal values, so ties go left.
            let column = bottoms.indices.min { bottoms[$0] < bottoms[$1] } ?? 0
            slots.append(Slot(column: column, y: bottoms[column]))
            bottoms[column] += height + spacing
        }
        self.slots = slots
        height = heights.isEmpty ? 0 : max((bottoms.max() ?? 0) - spacing, 0)
    }
}
