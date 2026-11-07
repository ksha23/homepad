import SwiftUI

/// A floating Liquid Glass container for panels and menus (Control Center,
/// the People menu, banners). Unlike `GlassTile` it does not stretch to fill
/// its space, so it hugs its content.
///
///     GlassPanel {
///         Text("People").font(.headline)
///     }
///
///     GlassPanel(cornerRadius: Theme.Radius.card, tint: .orange.opacity(0.3)) { ... }
public struct GlassPanel<Content: View>: View {
    private let cornerRadius: CGFloat
    private let padding: CGFloat
    private let tint: Color?
    private let isInteractive: Bool
    private let content: Content

    /// - Parameters:
    ///   - cornerRadius: Corner radius of the glass shape.
    ///   - padding: Inner padding around the content.
    ///   - tint: Optional color mixed into the glass.
    ///   - isInteractive: Makes the glass react to touches (press highlight), for tappable panels.
    public init(
        cornerRadius: CGFloat = Theme.Radius.tile, padding: CGFloat = Theme.Spacing.m,
        tint: Color? = nil, isInteractive: Bool = false, @ViewBuilder content: () -> Content
    ) {
        self.cornerRadius = cornerRadius
        self.padding = padding
        self.tint = tint
        self.isInteractive = isInteractive
        self.content = content()
    }

    public var body: some View {
        content
            .padding(padding)
            .tileGlassEffect(glass, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }

    private var glass: Glass {
        Glass.regular.tint(tint).interactive(isInteractive)
    }
}
