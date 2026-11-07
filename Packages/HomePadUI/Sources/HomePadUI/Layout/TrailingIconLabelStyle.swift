import SwiftUI

/// Puts a label's icon after its title, as in "Madison" followed by a
/// location arrow.
///
///     Label("Madison", systemImage: "location.fill").labelStyle(.trailingIcon)
public struct TrailingIconLabelStyle: LabelStyle {
    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 4) {
            configuration.title
            configuration.icon.imageScale(.small)
        }
    }
}

public extension LabelStyle where Self == TrailingIconLabelStyle {
    /// The icon after the title. See `TrailingIconLabelStyle`.
    static var trailingIcon: TrailingIconLabelStyle { TrailingIconLabelStyle() }
}
