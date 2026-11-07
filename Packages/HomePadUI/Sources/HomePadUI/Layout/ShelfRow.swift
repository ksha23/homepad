import SwiftUI

/// A titled horizontal row of tiles that scrolls sideways, like a shelf in
/// Apple Music. Fill it with `ArtworkTile`s.
///
///     ShelfRow("Stations") { ForEach(stations) { StationTile($0) } }
public struct ShelfRow<Content: View>: View {
    private let title: String
    private let content: Content

    /// - Parameters:
    ///   - title: Drawn as a `SectionHeader`.
    ///   - content: The tiles.
    public init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            SectionHeader(title)
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: Theme.Spacing.l) { content }
            }
            .scrollClipDisabled()
        }
    }
}
