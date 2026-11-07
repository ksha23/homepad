import HomePadUI
import SwiftUI

/// One city on the World Clock: the clock in the chosen style, the city name,
/// and how far ahead or behind home it is.
struct CityClockCard: View {
    let city: WorldClockCity
    let style: WorldClockStyle
    let date: Date
    var isHome = false
    /// Diameter of the clock. Nil lets it fill the card's width.
    var clockSize: CGFloat?

    /// Height of the name, offset and time under the clock.
    static let labelsHeight: CGFloat = 84

    var body: some View {
        let zone = city.timeZone
        // The minute rolls over in the digits only. The hands must not animate,
        // or the second hand would sweep back from 59 to 0.
        let time = TimeZoneMath.timeText(at: date, in: zone)
        VStack(spacing: Theme.Spacing.m) {
            switch style {
            case .analog:
                AnalogClock(date: date, timeZone: zone, dial: .numerals, showsSeconds: true,
                            isDaytime: TimeZoneMath.isDaytime(at: date, in: zone))
                    .frame(maxWidth: clockSize, maxHeight: clockSize)
            case .minimal:
                AnalogClock(date: date, timeZone: zone, dial: .ticks, showsSeconds: true,
                            isDaytime: TimeZoneMath.isDaytime(at: date, in: zone))
                    .frame(maxWidth: clockSize, maxHeight: clockSize)
            case .digital:
                Text(time)
                    // Proportional digits, as on the faces: tabular ones spread
                    // a time like 11:07 apart.
                    .font(.display(clockSize.map { min($0 * 0.32, 120) } ?? 72))
                    .contentTransition(.numericText())
                    .animation(Theme.Motion.standard, value: time)
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, minHeight: 120)
            }
            VStack(spacing: 2) {
                Text(city.name)
                    .font(.title2.weight(.semibold))
                    .lineLimit(1)
                Text(isHome ? "Here" : TimeZoneMath.subtitle(for: zone, from: .current, at: date))
                    .font(.headline)
                    .foregroundStyle(.secondary)
                if style != .digital {
                    Text(time)
                        .font(.title3.weight(.medium))
                        .contentTransition(.numericText())
                        .animation(Theme.Motion.standard, value: time)
                }
            }
        }
        .padding(Theme.Spacing.l)
        .frame(maxWidth: .infinity)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: Theme.Radius.tile, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}
