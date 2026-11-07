import CoreGraphics
import HomePadUI
import SwiftUI

/// How much room the controls under the editor's preview take for a page, so
/// the preview gets the rest and still shows the whole face.
enum EditorMetrics {
    /// The tallest a choice card's face thumbnail is.
    static let thumbnailHeight: CGFloat = 120
    /// The widest a choice card's face thumbnail is.
    static let thumbnailMaxWidth: CGFloat = 200
    /// The narrowest a choice card is.
    static let cardMinWidth: CGFloat = 180
    /// One line of a card's headline title.
    static let cardTitleHeight: CGFloat = 24
    /// The narrowest a slot card is before the grid drops a column.
    static let slotMinWidth: CGFloat = 220
    /// A slot card: its symbol's tap target and the card's padding.
    static let slotHeight = Theme.Size.minTapTarget + Theme.Spacing.m * 2
    /// One line of footnote under a page's controls (`FaceOption.note`).
    static let noteHeight: CGFloat = 20
    /// Share of the height a page the face draws itself gets (photo source, rules).
    static let customShare: CGFloat = 0.45
    /// A Color page's swatch and the gap to its ring, as `PaletteSwatchPicker`
    /// draws them. With the ring the target is 50 points, over `minTapTarget`.
    static let swatchSize: CGFloat = 40
    static let swatchRing: CGFloat = 5
    /// One row of a Color page: a swatch and the room for its ring.
    static let swatchRowHeight = swatchSize + swatchRing * 2
    /// The name and current color at the start of a Color page's row.
    static let colorLabelWidth: CGFloat = 120

    /// The size of a face thumbnail on a choice card, in the screen's shape.
    static func thumbnailSize(screen: CGSize) -> CGSize {
        let aspect = screen.width / max(screen.height, 1)
        let width = min(thumbnailMaxWidth, thumbnailHeight * aspect)
        return CGSize(width: width, height: width / max(aspect, 0.01))
    }

    /// The width of a choice card around a thumbnail of `size`.
    static func cardWidth(thumbnail size: CGSize) -> CGFloat {
        max(size.width + Theme.Spacing.m * 2, cardMinWidth)
    }

    /// Height of the controls for one page.
    /// - Parameters:
    ///   - screen: The screen the face is laid out on, for the shape of card thumbnails.
    ///   - width: The width the controls have.
    ///   - height: The height under the header, shared by the preview and the controls.
    static func controlsHeight(for option: FaceOption?, screen: CGSize, width: CGFloat, height: CGFloat) -> CGFloat {
        guard let option else { return Theme.Size.tapTarget }
        // A card: its picture, the gap, a title and the padding around them,
        // plus a little room so the selected card's outline is not cut off.
        let cardChrome = Theme.Spacing.s + cardTitleHeight + Theme.Spacing.m * 2 + Theme.Spacing.s
        switch option.kind {
        case .choices:
            let picture = option.cardStyle == .faceThumbnail
                ? thumbnailSize(screen: screen).height : OptionCard<EmptyView>.defaultIconSize.height
            return picture + cardChrome
        case .colors(_, let roles) where roles.isEmpty:
            return OptionCard<EmptyView>.defaultIconSize.height + cardChrome
        case .colors(_, let roles):
            // A row for the background and one for each other part, then the note.
            let rows = 1 + (roles.contains(.text) ? 1 : 0) + (roles.contains(.accent) ? 1 : 0)
            return CGFloat(rows) * swatchRowHeight + CGFloat(rows) * Theme.Spacing.xs + noteHeight
        case .slots(let slots, _):
            let rows = slotRows(count: slots.count, width: width)
            let note = option.note == nil ? 0 : Theme.Spacing.s + noteHeight
            return CGFloat(rows) * slotHeight + CGFloat(max(rows - 1, 0)) * Theme.Spacing.m + note
        case .custom:
            return (height * customShare).rounded()
        case .widgetGrid:
            // The Add Widget button with a line or two beside it on how to arrange widgets.
            return Theme.Size.tapTarget
        }
    }

    /// Columns of slot cards: as many as fit, spread so the rows come out even
    /// (four slots in two rows of two rather than three and one).
    static func slotColumns(count: Int, width: CGFloat) -> Int {
        guard count > 0 else { return 1 }
        let fit = max(1, Int((width + Theme.Spacing.m) / (slotMinWidth + Theme.Spacing.m)))
        let rows = (count + fit - 1) / fit
        return (count + rows - 1) / rows
    }

    /// Rows of slot cards at `slotColumns`.
    static func slotRows(count: Int, width: CGFloat) -> Int {
        let columns = slotColumns(count: count, width: width)
        return (count + columns - 1) / columns
    }
}
