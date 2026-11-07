import SwiftUI

/// A small glass capsule that states a condition, for example "Not charging"
/// or "Camera off". Use it for persistent, non-blocking notices.
///
///     StatusBanner("HomePad is not charging", systemImage: "battery.25", tint: .orange)
public struct StatusBanner: View {
    private let message: String
    private let systemImage: String
    private let tint: Color

    /// - Parameters:
    ///   - message: One short sentence.
    ///   - systemImage: SF Symbol shown before the message.
    ///   - tint: Color of the symbol.
    public init(_ message: String, systemImage: String, tint: Color = .yellow) {
        self.message = message
        self.systemImage = systemImage
        self.tint = tint
    }

    public var body: some View {
        Label {
            Text(message).foregroundStyle(.primary)
        } icon: {
            Image(systemName: systemImage).foregroundStyle(tint)
        }
        .font(.title3.weight(.semibold))
        .padding(.horizontal, Theme.Spacing.m)
        .padding(.vertical, Theme.Spacing.s)
        .glassEffect(.regular, in: Capsule())
        .accessibilityElement(children: .combine)
    }
}
