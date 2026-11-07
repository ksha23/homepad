@testable import HomePadKitchen
import Testing

/// The timers widget tries ways to fill its tile in a ViewThatFits. Two views
/// with the same identity there stop the app.
@MainActor
struct RunningTimersWidgetTests {
    @Test func everyWayToFillTheTileIsDistinct() {
        for rows in 1...3 {
            for limit in 0...6 {
                let candidates = RunningTimersWidget.candidates(limit: limit, rows: rows)
                #expect(Set(candidates).count == candidates.count, "rows \(rows), limit \(limit)")
                #expect(!candidates.isEmpty)
            }
        }
    }

    @Test func fullestComesFirst() {
        let candidates = RunningTimersWidget.candidates(limit: 3, rows: 2)
        #expect(candidates.first == .init(count: 3, presets: KitchenSettings.maxPresets))
        #expect(candidates.last == .init(count: 1, presets: 0))
    }

    @Test func oneRowNeverOffersPresets() {
        #expect(RunningTimersWidget.candidates(limit: 2, rows: 1).allSatisfy { $0.presets == 0 })
    }
}
