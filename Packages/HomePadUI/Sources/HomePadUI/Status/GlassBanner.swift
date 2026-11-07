import HomePadCore
import SwiftUI

/// A floating Liquid Glass card for something that just happened: an
/// intercom message, a shared photo, a sound HomePad heard, a speaker
/// suggestion. It has a tinted icon, a title, a detail line, optional
/// content and trailing actions (`GlassIconButton`s or a `GlassCapsuleButton`).
///
/// From across the room the text grows so it can be read at a glance.
/// Place it with padding and a transition at the call site:
///
///     GlassBanner(systemImage: "waveform", tint: .green, title: "Intercom from Kitchen",
///                 subtitle: "Dinner is ready") {
///         EmptyView()
///     } actions: {
///         CloseButton("Dismiss") { dismiss() }
///     }
///     .padding(Theme.Spacing.l)
///     .transition(.move(edge: .top).combined(with: .opacity))
///
/// Use `StatusBanner` for a persistent condition instead.
public struct GlassBanner<Content: View, Actions: View>: View {
    private let systemImage: String
    private let tint: Color
    private let title: String
    private let subtitle: String?
    private let content: Content
    private let actions: Actions
    @Environment(\.proximity) private var proximity

    /// - Parameters:
    ///   - systemImage: SF Symbol drawn white in a circle of `tint`.
    ///   - tint: Color of the icon circle.
    ///   - title: One short line.
    ///   - subtitle: Optional detail, up to three lines.
    ///   - content: Optional content under the text, such as a photo.
    ///   - actions: Optional trailing buttons.
    public init(
        systemImage: String, tint: Color = .accentColor, title: String, subtitle: String? = nil,
        @ViewBuilder content: () -> Content = { EmptyView() },
        @ViewBuilder actions: () -> Actions = { EmptyView() }
    ) {
        self.systemImage = systemImage
        self.tint = tint
        self.title = title
        self.subtitle = subtitle
        self.content = content()
        self.actions = actions()
    }

    public var body: some View {
        let isFar = proximity <= .far
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            HStack(spacing: Theme.Spacing.m) {
                Image(systemName: systemImage)
                    .font(.system(size: Theme.Size.tapTarget * 0.45, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: Theme.Size.tapTarget, height: Theme.Size.tapTarget)
                    .background(tint.gradient, in: Circle())
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(isFar ? .largeTitle.bold() : .title2.bold())
                        .lineLimit(2)
                    if let subtitle {
                        Text(subtitle)
                            .font(isFar ? .title2 : .title3)
                            .foregroundStyle(.secondary)
                            .lineLimit(3)
                    }
                }
                Spacer(minLength: Theme.Spacing.m)
                HStack(spacing: Theme.Spacing.s) { actions }
            }
            content
        }
        .animation(Theme.Motion.screen, value: isFar)
        .padding(Theme.Spacing.l)
        .frame(maxWidth: 720)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: Theme.Radius.tile, style: .continuous))
        .nightModeAware()
        .accessibilityElement(children: .contain)
    }
}
