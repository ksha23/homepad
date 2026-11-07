import SwiftUI

/// A large glass tile for a launcher grid: an app-style icon, a title, a
/// one-line description and an optional status line, like the tools in
/// Camera Lab. Wrap it in a `Button` or `NavigationLink`.
///
///     FeatureTile(title: "QR Scanner", subtitle: "Wi-Fi details and links",
///                 systemImage: "qrcode.viewfinder", tint: .blue, status: "Ready")
public struct FeatureTile: View {
    private let title: String
    private let subtitle: String
    private let systemImage: String
    private let tint: Color
    private let status: String?
    private let isActive: Bool

    /// - Parameters:
    ///   - title: The feature's name.
    ///   - subtitle: One short sentence about it.
    ///   - systemImage: SF Symbol for the icon.
    ///   - tint: Icon color, also used for the status line.
    ///   - status: Optional live status ("Demo feed", "3 watching").
    ///   - isActive: Shows a pulsing "On" badge, for features running in the background.
    public init(
        title: String, subtitle: String, systemImage: String, tint: Color,
        status: String? = nil, isActive: Bool = false
    ) {
        self.title = title
        self.subtitle = subtitle
        self.systemImage = systemImage
        self.tint = tint
        self.status = status
        self.isActive = isActive
    }

    public var body: some View {
        GlassTile {
            VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                HStack(alignment: .top) {
                    AppIcon(systemImage: systemImage, tint: tint, size: Theme.Size.tapTarget)
                    Spacer()
                    if isActive {
                        StatusBadge("On", color: tint, pulses: true)
                    }
                }
                Spacer(minLength: Theme.Spacing.s)
                Text(title)
                    .font(.title2.weight(.semibold))
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
                Text(subtitle)
                    .font(.tileDetail)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                if let status {
                    Text(status)
                        .font(.tileDetail.weight(.medium))
                        .foregroundStyle(tint)
                        .lineLimit(1)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }
}
