import SwiftUI

/// Page indicator dots on a glass capsule, like the iPadOS Home Screen and
/// HomeView's cooking steps. Tapping a dot selects that page. Long
/// sequences show a window of dots around the current page.
///
///     PageDots(count: pages.count, selection: $page)
public struct PageDots: View {
    private let count: Int
    @Binding private var selection: Int
    private let maxVisible: Int

    /// Height of the capsule: a dot and its padding above and below.
    public static let height: CGFloat = dotSize + verticalPadding * 2
    private static let dotSize: CGFloat = 10
    private static let verticalPadding: CGFloat = 10

    /// - Parameters:
    ///   - count: Number of pages. Nothing is drawn for one page or fewer.
    ///   - selection: Index of the current page.
    ///   - maxVisible: Most dots shown at once. Longer sequences scroll the window.
    public init(count: Int, selection: Binding<Int>, maxVisible: Int = 15) {
        self.count = count
        self._selection = selection
        self.maxVisible = max(maxVisible, 1)
    }

    public var body: some View {
        if count > 1 {
            HStack(spacing: 12) {
                ForEach(visibleRange, id: \.self) { index in
                    Circle()
                        .fill(index == selection ? Color.primary : Color.primary.opacity(0.35))
                        .frame(width: Self.dotSize, height: Self.dotSize)
                        .contentShape(Rectangle().inset(by: -8))
                        .onTapGesture { selection = index }
                        .accessibilityLabel("Page \(index + 1) of \(count)")
                        .accessibilityAddTraits(index == selection ? .isSelected : [])
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, Self.verticalPadding)
            .glassEffect(.regular, in: Capsule())
            .animation(.smooth, value: selection)
        }
    }

    private var visibleRange: Range<Int> {
        guard count > maxVisible else { return 0..<count }
        let start = min(max(0, selection - maxVisible / 2), count - maxVisible)
        return start..<(start + maxVisible)
    }
}
