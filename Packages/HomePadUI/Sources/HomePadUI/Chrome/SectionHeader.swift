import SwiftUI

/// A labeled section header used over groups of tiles and rows, in Title 3
/// so it reads from arm's length like the tile titles under it.
///
///     SectionHeader("Favorites", systemImage: "star.fill")
public struct SectionHeader: View {
    private let title: String
    private let systemImage: String?

    /// - Parameters:
    ///   - title: The section name.
    ///   - systemImage: Optional SF Symbol before the title.
    public init(_ title: String, systemImage: String? = nil) {
        self.title = title
        self.systemImage = systemImage
    }

    public var body: some View {
        HStack(spacing: Theme.Spacing.xs) {
            if let systemImage { Image(systemName: systemImage) }
            Text(title)
        }
        .font(.title3.weight(.semibold))
        .foregroundStyle(.secondary)
        .textCase(nil)
    }
}
