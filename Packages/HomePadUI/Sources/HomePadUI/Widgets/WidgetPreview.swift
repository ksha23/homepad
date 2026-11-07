import HomePadCore
import SwiftUI

/// A live widget drawn at its real size and scaled to fit a box, so a
/// preview looks exactly like the widget where it will sit. Used by
/// `WidgetGallery`.
///
///     WidgetPreview(tile: CGSize(width: 344, height: 160), fitting: CGSize(width: 300, height: 200)) {
///         widget.makeView(.medium)
///     }
public struct WidgetPreview<Content: View>: View {
    private let tile: CGSize
    private let box: CGSize
    private let content: Content

    /// - Parameters:
    ///   - tile: The size the widget is drawn at where it will sit.
    ///   - box: The most room the preview may take. It never draws larger than `tile`.
    ///   - content: The widget, drawn to fill `tile`.
    public init(tile: CGSize, fitting box: CGSize, @ViewBuilder content: () -> Content) {
        self.tile = CGSize(width: max(tile.width, 1), height: max(tile.height, 1))
        self.box = box
        self.content = content()
    }

    public var body: some View {
        let scale = Self.scale(tile: tile, box: box)
        content
            .frame(width: tile.width, height: tile.height)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.tile, style: .continuous))
            .scaleEffect(scale, anchor: .topLeading)
            .frame(width: tile.width * scale, height: tile.height * scale, alignment: .topLeading)
            .environment(\.isThumbnail, true)
            .allowsHitTesting(false)
    }

    /// The scale that fits `tile` in `box`, at most 1.
    public static func scale(tile: CGSize, box: CGSize) -> CGFloat {
        max(min(box.width / max(tile.width, 1), box.height / max(tile.height, 1), 1), 0.01)
    }
}
