import HomePadCore
import HomePadUI
import SwiftUI

/// Analog clocks for the household's World Clock cities: one (small), four in
/// a row (medium, like HomeView's four-city widget) or a 2 by 2 grid (large).
struct WorldClockWidgetView: View {
    @Environment(WorldClockStore.self) private var clocks
    let size: WidgetSize

    var body: some View {
        GlassTile {
            // The clocks have no second hand, so they move on the minute.
            ClockTimeline(every: .minute) { now in
                let cities = Array(clocks.cities.prefix(size == .small ? 1 : 4))
                if cities.isEmpty {
                    Text("Add cities in World Clock").font(.headline).foregroundStyle(.secondary)
                } else if size == .large {
                    Grid(horizontalSpacing: Theme.Spacing.m, verticalSpacing: Theme.Spacing.m) {
                        GridRow { ForEach(cities.prefix(2)) { cell($0, date: now) } }
                        GridRow { ForEach(cities.dropFirst(2)) { cell($0, date: now) } }
                    }
                } else {
                    HStack(spacing: Theme.Spacing.m) {
                        ForEach(cities) { cell($0, date: now) }
                    }
                }
            }
        }
    }

    private func cell(_ city: WorldClockCity, date: Date) -> some View {
        VStack(spacing: Theme.Spacing.xs) {
            AnalogClock(date: date, timeZone: city.timeZone, isDaytime: TimeZoneMath.isDaytime(at: date, in: city.timeZone))
            Text(city.name).font(.headline).lineLimit(1).minimumScaleFactor(0.7)
            Text(TimeZoneMath.offsetText(seconds: TimeZoneMath.offset(of: city.timeZone, from: .current, at: date)))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity)
    }
}
