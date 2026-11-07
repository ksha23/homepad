import CoreGraphics
import HomePadUI
import Testing
@testable import HomePadPersonal

/// In landscape on iPad, the Weather app displays the header and hourly
/// conditions panel in the left column and the 10-day forecast panel in the
/// right column. The two columns must align cleanly at their bottom edges
/// without hardcoding heights.
@Suite struct WeatherWideTopLayoutTests {
    @Test func equalizesHeightsWhenDailyIsTaller() {
        let metrics = WeatherWideTopMetrics(
            availableWidth: 1250,
            spacing: Theme.Spacing.l, // 24
            headerSize: CGSize(width: 300, height: 230),
            conditionsNaturalHeight: 200,
            dailyNaturalHeight: 530
        )

        // Total height matches the taller right column
        #expect(metrics.totalHeight == 530)
        #expect(metrics.dailyFrame.height == 530)

        // Conditions panel expands down so its bottom edge exactly aligns with daily
        #expect(metrics.conditionsFrame.minY == 230 + Theme.Spacing.l)
        #expect(metrics.conditionsFrame.height == 530 - 230 - Theme.Spacing.l)
        #expect(metrics.conditionsFrame.maxY == metrics.dailyFrame.maxY)
        #expect(metrics.conditionsFrame.maxY == 530)
    }

    @Test func equalizesHeightsWhenLeftColumnIsTaller() {
        let metrics = WeatherWideTopMetrics(
            availableWidth: 1250,
            spacing: Theme.Spacing.l, // 24
            headerSize: CGSize(width: 300, height: 250),
            conditionsNaturalHeight: 210,
            dailyNaturalHeight: 350
        )

        // Natural left height = 250 + 24 + 210 = 484
        #expect(metrics.totalHeight == 484)

        // Daily panel expands to match the taller left column
        #expect(metrics.dailyFrame.height == 484)
        #expect(metrics.conditionsFrame.height == 210)
        #expect(metrics.conditionsFrame.maxY == metrics.dailyFrame.maxY)
        #expect(metrics.conditionsFrame.maxY == 484)
    }

    @Test func columnWidthsCoverTotalWidthAndHonorMinimumWidth() {
        // Wide iPad: 36% of 1600 is 576, which exceeds minimumWidth (434)
        let wideMetrics = WeatherWideTopMetrics(
            availableWidth: 1600,
            spacing: Theme.Spacing.l,
            dailyWidthRatio: 0.36,
            dailyMinWidth: DailyForecastPanel.minimumWidth,
            headerSize: CGSize(width: 300, height: 200),
            conditionsNaturalHeight: 200,
            dailyNaturalHeight: 500
        )
        let expectedRight = 1600 * 0.36
        #expect(abs(wideMetrics.rightWidth - expectedRight) < 0.001)
        #expect(abs(wideMetrics.leftWidth - (1600 - expectedRight - Theme.Spacing.l)) < 0.001)
        #expect(abs((wideMetrics.leftWidth + wideMetrics.spacing + wideMetrics.rightWidth) - 1600) < 0.001)

        // Narrower: clamped to DailyForecastPanel.minimumWidth
        let narrowMetrics = WeatherWideTopMetrics(
            availableWidth: 900,
            spacing: Theme.Spacing.l,
            dailyWidthRatio: 0.36,
            dailyMinWidth: DailyForecastPanel.minimumWidth,
            headerSize: CGSize(width: 300, height: 200),
            conditionsNaturalHeight: 200,
            dailyNaturalHeight: 500
        )
        #expect(abs(narrowMetrics.rightWidth - DailyForecastPanel.minimumWidth) < 0.001)
        #expect(abs(narrowMetrics.leftWidth - (900 - DailyForecastPanel.minimumWidth - Theme.Spacing.l)) < 0.001)
        #expect(abs((narrowMetrics.leftWidth + narrowMetrics.spacing + narrowMetrics.rightWidth) - 900) < 0.001)
    }

    @Test func headerIsHorizontallyCenteredInLeftColumn() {
        let metrics = WeatherWideTopMetrics(
            availableWidth: 1250,
            spacing: Theme.Spacing.l,
            headerSize: CGSize(width: 300, height: 220),
            conditionsNaturalHeight: 200,
            dailyNaturalHeight: 500
        )

        let expectedX = (metrics.leftWidth - 300) / 2
        #expect(abs(metrics.headerFrame.minX - expectedX) < 0.001)
        #expect(metrics.headerFrame.width == 300)
        #expect(metrics.headerFrame.height == 220)
    }

    @Test func neitherPanelIsEverCompressedBelowNaturalHeight() {
        let combinations: [(daily: CGFloat, header: CGFloat, conditions: CGFloat)] = [
            (500, 200, 200),
            (300, 200, 200),
            (600, 300, 250),
            (200, 150, 150),
        ]

        for (dailyH, headerH, conditionsH) in combinations {
            let metrics = WeatherWideTopMetrics(
                availableWidth: 1250,
                spacing: Theme.Spacing.l,
                headerSize: CGSize(width: 250, height: headerH),
                conditionsNaturalHeight: conditionsH,
                dailyNaturalHeight: dailyH
            )
            #expect(metrics.conditionsFrame.height >= conditionsH)
            #expect(metrics.dailyFrame.height >= dailyH)
            #expect(metrics.conditionsFrame.maxY == metrics.dailyFrame.maxY)
        }
    }
}
