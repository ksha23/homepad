import HomePadUI
import SwiftUI

/// Pure geometry math for the Weather app's landscape top section, sizing
/// and aligning the header, hourly conditions panel, and 10-day daily forecast
/// panel.
struct WeatherWideTopMetrics: Equatable {
    let availableWidth: CGFloat
    let spacing: CGFloat
    let leftWidth: CGFloat
    let rightWidth: CGFloat
    let headerFrame: CGRect
    let conditionsFrame: CGRect
    let dailyFrame: CGRect
    let totalHeight: CGFloat

    init(
        availableWidth: CGFloat,
        spacing: CGFloat = Theme.Spacing.l,
        dailyWidthRatio: CGFloat = 0.36,
        dailyMinWidth: CGFloat = DailyForecastPanel.minimumWidth,
        headerSize: CGSize,
        conditionsNaturalHeight: CGFloat,
        dailyNaturalHeight: CGFloat
    ) {
        self.availableWidth = availableWidth
        self.spacing = spacing

        let right = min(availableWidth, max(availableWidth * dailyWidthRatio, dailyMinWidth))
        let left = max(0, availableWidth - right - spacing)
        self.leftWidth = left
        self.rightWidth = right

        let leftNaturalHeight = headerSize.height + spacing + conditionsNaturalHeight
        let total = max(dailyNaturalHeight, leftNaturalHeight)
        self.totalHeight = total

        let headerX = max(0, (left - headerSize.width) / 2)
        self.headerFrame = CGRect(x: headerX, y: 0, width: headerSize.width, height: headerSize.height)

        let conditionsY = headerSize.height + spacing
        let conditionsHeight = max(0, total - conditionsY)
        self.conditionsFrame = CGRect(x: 0, y: conditionsY, width: left, height: conditionsHeight)

        let dailyX = left + spacing
        self.dailyFrame = CGRect(x: dailyX, y: 0, width: right, height: total)
    }
}

/// In landscape, lays out the Weather app's top section: the header and
/// hourly Conditions panel in the left column, and the 10-day forecast panel
/// in the right column.
///
/// Both columns are given matching total heights so that the Conditions panel
/// and the 10-day forecast panel align cleanly along their bottom edges.
struct WeatherWideTopLayout: Layout {
    /// Horizontal gap between the left column and right column, and vertical
    /// gap between the header and the Conditions panel.
    var spacing: CGFloat = Theme.Spacing.l

    /// The proportion of total width given to the 10-day forecast panel when
    /// wider than its minimum width.
    var dailyWidthRatio: CGFloat = 0.36

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard subviews.count == 3 else {
            return fallbackSize(proposal: proposal, subviews: subviews)
        }
        let metrics = computeMetrics(for: proposal.width ?? 0, subviews: subviews)
        return CGSize(width: metrics.availableWidth, height: metrics.totalHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard subviews.count == 3 else {
            fallbackPlace(in: bounds, proposal: proposal, subviews: subviews)
            return
        }
        let metrics = computeMetrics(for: bounds.width, subviews: subviews)

        let header = subviews[0]
        let conditions = subviews[1]
        let daily = subviews[2]

        header.place(
            at: CGPoint(x: bounds.minX + metrics.headerFrame.minX, y: bounds.minY + metrics.headerFrame.minY),
            proposal: ProposedViewSize(metrics.headerFrame.size)
        )

        conditions.place(
            at: CGPoint(x: bounds.minX + metrics.conditionsFrame.minX, y: bounds.minY + metrics.conditionsFrame.minY),
            proposal: ProposedViewSize(metrics.conditionsFrame.size)
        )

        daily.place(
            at: CGPoint(x: bounds.minX + metrics.dailyFrame.minX, y: bounds.minY + metrics.dailyFrame.minY),
            proposal: ProposedViewSize(metrics.dailyFrame.size)
        )
    }

    private func computeMetrics(for width: CGFloat, subviews: Subviews) -> WeatherWideTopMetrics {
        let right = min(width, max(width * dailyWidthRatio, DailyForecastPanel.minimumWidth))
        let left = max(0, width - right - spacing)

        let header = subviews[0]
        let conditions = subviews[1]
        let daily = subviews[2]

        let headerSize = header.sizeThatFits(ProposedViewSize(width: left, height: nil))
        let conditionsNaturalSize = conditions.sizeThatFits(ProposedViewSize(width: left, height: nil))
        let dailySize = daily.sizeThatFits(ProposedViewSize(width: right, height: nil))

        return WeatherWideTopMetrics(
            availableWidth: width,
            spacing: spacing,
            dailyWidthRatio: dailyWidthRatio,
            dailyMinWidth: DailyForecastPanel.minimumWidth,
            headerSize: headerSize,
            conditionsNaturalHeight: conditionsNaturalSize.height,
            dailyNaturalHeight: dailySize.height
        )
    }

    private func fallbackSize(proposal: ProposedViewSize, subviews: Subviews) -> CGSize {
        var maxHeight: CGFloat = 0
        var totalWidth: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(proposal)
            maxHeight = max(maxHeight, size.height)
            totalWidth += size.width + spacing
        }
        return CGSize(width: proposal.width ?? max(0, totalWidth - spacing), height: maxHeight)
    }

    private func fallbackPlace(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews) {
        var x = bounds.minX
        for subview in subviews {
            let size = subview.sizeThatFits(proposal)
            subview.place(at: CGPoint(x: x, y: bounds.minY), proposal: ProposedViewSize(size))
            x += size.width + spacing
        }
    }
}
