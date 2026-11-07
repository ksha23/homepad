import SwiftUI

/// The header of a full-screen detail inside an app, such as a camera, an
/// accessory or cooking mode: the title and a status line on the leading side,
/// the toolbar and the close button on the trailing side, and optional detail
/// content (step dots) centered under the row. It lays out like `AppHeader`,
/// so the top center stays free for the Now Playing pill and the items take
/// the toolbar size and degrade the same way.
///
/// It tells the shell that the screen draws its own close button, so a
/// detail never shows two. Closing a detail returns to the app.
/// `AppScreen` is for the app itself.
///
///     DetailHeader("Back Yard", subtitle: "Live", onClose: { selected = nil }, trailing: {
///         GlassIconButton("speaker.wave.2.fill", label: "Mute") { isMuted.toggle() }
///     })
///
/// Label `detail:` and `trailing:` when passing only one of them.
public struct DetailHeader<Detail: View, Trailing: View>: View {
    private let title: String
    private let subtitle: String?
    private let closeLabel: String
    private let onClose: () -> Void
    private let detail: Detail
    private let trailing: Trailing

    /// - Parameters:
    ///   - title: The detail's name.
    ///   - subtitle: Optional status line under the title.
    ///   - closeLabel: What VoiceOver reads for the close button.
    ///   - onClose: Leaves the detail.
    ///   - detail: Optional content centered under the row, such as step dots.
    ///   - trailing: Optional toolbar items drawn before the close button.
    public init(
        _ title: String, subtitle: String? = nil, closeLabel: String = "Close", onClose: @escaping () -> Void,
        @ViewBuilder detail: () -> Detail = { EmptyView() },
        @ViewBuilder trailing: () -> Trailing = { EmptyView() }
    ) {
        self.title = title
        self.subtitle = subtitle
        self.closeLabel = closeLabel
        self.onClose = onClose
        self.detail = detail()
        self.trailing = trailing()
    }

    public var body: some View {
        VStack(spacing: Theme.Spacing.s) {
            HeaderRow {
                titles
            } trailing: {
                HeaderTrailing(items: trailing, close: CloseButton(closeLabel, action: onClose))
            }
            .dynamicTypeSize(...ToolbarMetrics.largestTypeSize)
            detail
        }
        .preference(key: AppDrawsCloseButtonKey.self, value: true)
    }

    private var titles: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.title2.weight(.semibold))
                .accessibilityAddTraits(.isHeader)
            if let subtitle {
                Text(subtitle)
                    .font(.headline)
                    .foregroundStyle(.secondary)
                    .contentTransition(.numericText())
            }
        }
        .lineLimit(1)
        .minimumScaleFactor(0.7)
        .frame(minHeight: Theme.Size.toolbarItem)
    }
}
