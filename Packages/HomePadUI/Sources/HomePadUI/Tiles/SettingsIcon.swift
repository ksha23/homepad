import SwiftUI

/// The small rounded icon square that leads a row in iOS Settings: a white
/// symbol on a tinted gradient. Use it in `Form` and `List` rows. Use
/// `AppIcon` on the Home Screen and in galleries.
///
///     Label { Text("AI Assistant") } icon: { SettingsIcon(systemImage: "sparkles", tint: .indigo) }
public struct SettingsIcon: View {
    private let systemImage: String
    private let tint: Color
    private let size: CGFloat

    /// - Parameters:
    ///   - systemImage: SF Symbol name.
    ///   - tint: Background color. A gradient is derived from it.
    ///   - size: Edge length in points.
    public init(systemImage: String, tint: Color, size: CGFloat = 32) {
        self.systemImage = systemImage
        self.tint = tint
        self.size = size
    }

    public var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: size * 0.5, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(tint.gradient, in: RoundedRectangle(cornerRadius: Theme.Radius.icon(size), style: .continuous))
            .accessibilityHidden(true)
    }
}
