import HomePadCore
import HomePadUI
import SwiftUI

/// The next hours in a glass card, shown when someone steps close to the
/// Weather face (HomeView's near view).
struct HourlyStrip: View {
    let hours: [WeatherSnapshot.Hour]
    let palette: FacePalette?
    /// The zone the hours read in: a chosen city's, or the iPad's.
    var timeZone: TimeZone = .current

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            Label("Hourly Forecast", systemImage: "clock")
                .font(.headline)
                .foregroundStyle(.secondary)
            HStack(spacing: 0) {
                ForEach(Array(hours.prefix(8).enumerated()), id: \.offset) { index, hour in
                    VStack(spacing: Theme.Spacing.s) {
                        Text(index == 0 ? "Now" : hour.date.formatted(Date.FormatStyle(timeZone: timeZone).hour()))
                            .font(.title3.weight(.semibold))
                        Image(systemName: hour.symbolName)
                            .symbolRenderingMode(palette?.isNight == true ? .monochrome : .multicolor)
                            .font(.title)
                            .frame(height: 40)
                        Text("\(Int(hour.temperature.rounded()))°")
                            .font(.title2.weight(.semibold))
                            .monospacedDigit()
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .foregroundStyle(palette?.ink ?? .white)
        .padding(Theme.Spacing.l)
        .glassEffect(in: RoundedRectangle(cornerRadius: Theme.Radius.tile, style: .continuous))
        // The sky is a picture, so its text is white in Light and Dark, as in
        // the Weather app. Glass that turned light, in Light or over a bright
        // sky, would wash it out, so the card's glass stays dark.
        .environment(\.colorScheme, .dark)
    }
}

/// Plausible hourly data for the demo weather service, which has none.
/// Only used when `services.weather` is still Core's demo service.
enum DemoForecast {
    /// The next hours to show: the snapshot's own forecast, or plausible ones
    /// when `services.weather` is Core's demo service.
    @MainActor
    static func hours(for weather: WeatherSnapshot, service: any WeatherService, now: Date) -> [WeatherSnapshot.Hour] {
        if !weather.hourly.isEmpty { return weather.hourly }
        return service is DemoWeatherService ? hourly(from: weather, now: now) : []
    }

    static func hourly(from snapshot: WeatherSnapshot, now: Date, calendar: Calendar = .current) -> [WeatherSnapshot.Hour] {
        let start = calendar.dateInterval(of: .hour, for: now)?.start ?? now
        let high = snapshot.high ?? snapshot.temperature + 3
        let low = snapshot.low ?? snapshot.temperature - 5
        return (0..<8).map { offset in
            let date = start.addingTimeInterval(TimeInterval(offset * 3600))
            let hour = Double(calendar.component(.hour, from: date))
            // Warmest mid-afternoon, coolest before dawn.
            let warmth = (cos((hour - 15) / 24 * 2 * .pi) + 1) / 2
            let temperature = offset == 0 ? snapshot.temperature : low + (high - low) * warmth
            let isNight = hour < 7 || hour >= 19
            let symbol = offset == 0 ? snapshot.symbolName : (isNight ? "moon.stars.fill" : (offset % 3 == 0 ? "cloud.sun.fill" : "sun.max.fill"))
            return WeatherSnapshot.Hour(date: date, temperature: temperature, symbolName: symbol)
        }
    }
}
