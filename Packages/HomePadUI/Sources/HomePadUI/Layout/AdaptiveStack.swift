import SwiftUI

/// Side by side when the space is wider than tall, stacked otherwise, so a
/// two-pane app screen works in landscape and portrait without duplicate code.
///
///     AdaptiveStack(spacing: Theme.Spacing.xl) {
///         TimerFocusView()
///         TimerList()
///     }
public struct AdaptiveStack<Content: View>: View {
    private let spacing: CGFloat
    private let content: () -> Content

    /// - Parameters:
    ///   - spacing: Gap between the panes.
    ///   - content: The panes, in reading order.
    public init(spacing: CGFloat = Theme.Spacing.l, @ViewBuilder content: @escaping () -> Content) {
        self.spacing = spacing
        self.content = content
    }

    public var body: some View {
        GeometryReader { proxy in
            let layout = proxy.size.width >= proxy.size.height
                ? AnyLayout(HStackLayout(alignment: .top, spacing: spacing))
                : AnyLayout(VStackLayout(alignment: .center, spacing: spacing))
            layout { content() }
                .frame(width: proxy.size.width, height: proxy.size.height, alignment: .top)
        }
    }
}
