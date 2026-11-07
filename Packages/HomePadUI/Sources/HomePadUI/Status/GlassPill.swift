import SwiftUI

/// A small glass capsule with an optional symbol and a short text: the
/// assistant's provider name, a hardware feature, a room. Put a trailing
/// symbol or value in `trailing`.
///
///     GlassPill("Claude", systemImage: "sparkles")
///     GlassPill("LiDAR", systemImage: "dot.radiowaves.left.and.right") {
///         Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
///     }
public struct GlassPill<Trailing: View>: View {
    private let text: String
    private let systemImage: String?
    private let trailing: Trailing

    /// - Parameters:
    ///   - text: A word or two.
    ///   - systemImage: Optional SF Symbol before the text.
    ///   - trailing: Optional content after the text, such as a status symbol.
    public init(_ text: String, systemImage: String? = nil, @ViewBuilder trailing: () -> Trailing = { EmptyView() }) {
        self.text = text
        self.systemImage = systemImage
        self.trailing = trailing()
    }

    public var body: some View {
        HStack(spacing: Theme.Spacing.xs) {
            if let systemImage { Image(systemName: systemImage) }
            Text(text).lineLimit(1)
            trailing
        }
        .font(.body.weight(.medium))
        .padding(.horizontal, Theme.Spacing.m)
        .padding(.vertical, Theme.Spacing.s)
        .glassEffect(.regular, in: Capsule())
        .accessibilityElement(children: .combine)
    }
}
