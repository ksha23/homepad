import HomePadUI
import SwiftUI

/// The 10-day forecast with temperature range bars, like Apple Weather.
struct DailyForecastPanel: View {
    let days: [DailyForecast]
    /// Current temperature, drawn as a dot on today's bar.
    let current: Double
    let units: WeatherUnitSystem
    let timeZone: TimeZone

    private static let dayWidth: CGFloat = 90
    private static let symbolWidth: CGFloat = 48
    private static let temperatureWidth: CGFloat = 52

    /// The narrowest the panel draws without its rows spilling past its edges:
    /// the fixed columns, the range bar at its narrowest, the gaps between
    /// them and the padding. A layout that sizes the panel must give it this.
    static let minimumWidth = dayWidth + symbolWidth + temperatureWidth * 2 + TemperatureRangeBar.minimumWidth
        + Theme.Spacing.m * 4 + Theme.Spacing.l * 2

    var body: some View {
        let lowest = days.map(\.low).min() ?? 0
        let highest = days.map(\.high).max() ?? 1
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            Label("\(days.count)-Day Forecast", systemImage: "calendar")
                .font(.headline)
                .foregroundStyle(.secondary)
            ForEach(Array(days.enumerated()), id: \.element.id) { index, day in
                if index > 0 { Divider().overlay(.white.opacity(0.2)) }
                row(day, isToday: index == 0, lowest: lowest, highest: highest)
            }
        }
        .padding(Theme.Spacing.l)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .glassEffect(.regular.tint(.blue.opacity(0.15)), in: RoundedRectangle(cornerRadius: Theme.Radius.tile, style: .continuous))
    }

    private func row(_ day: DailyForecast, isToday: Bool, lowest: Double, highest: Double) -> some View {
        HStack(spacing: Theme.Spacing.m) {
            Text(isToday ? "Today" : dayName(day.date))
                .font(.title3.weight(.semibold))
                .frame(width: Self.dayWidth, alignment: .leading)
            VStack(spacing: 0) {
                Image(systemName: day.condition.symbolName())
                    .symbolRenderingMode(.multicolor)
                    .font(.title2)
                if let chance = day.precipitationChance, chance >= 0.2 {
                    Text("\(Int((chance * 100).rounded()))%")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(.cyan)
                }
            }
            .frame(width: Self.symbolWidth)
            Text(units.temperatureText(day.low))
                .font(.title3.weight(.medium))
                .foregroundStyle(.secondary)
                .frame(width: Self.temperatureWidth, alignment: .trailing)
            TemperatureRangeBar(low: day.low, high: day.high, lowest: lowest, highest: highest, marker: isToday ? current : nil)
            Text(units.temperatureText(day.high))
                .font(.title3.weight(.medium))
                .frame(width: Self.temperatureWidth, alignment: .trailing)
        }
        .monospacedDigit()
        .accessibilityElement(children: .combine)
    }

    private func dayName(_ date: Date) -> String {
        var style = Date.FormatStyle.dateTime.weekday(.abbreviated)
        style.timeZone = timeZone
        return date.formatted(style)
    }
}
