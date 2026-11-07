import HomePadUI
import SwiftUI

/// Detail tiles: feels like, humidity, wind, UV index, sunrise and sunset, pressure.
struct WeatherDetailGrid: View {
    let forecast: WeatherForecast
    let units: WeatherUnitSystem
    var columns = 2

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: Theme.Spacing.m), count: columns), spacing: Theme.Spacing.m) {
            ForEach(tiles, id: \.title) { tile in
                VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                    Label(tile.title, systemImage: tile.systemImage)
                        .font(.headline)
                        .foregroundStyle(.secondary)
                    Text(tile.value)
                        .font(.display(40))
                        .minimumScaleFactor(0.6)
                        .lineLimit(1)
                    if let detail = tile.detail {
                        Text(detail).font(.tileDetail).foregroundStyle(.secondary).lineLimit(2)
                    }
                    Spacer(minLength: 0)
                }
                .padding(Theme.Spacing.m)
                .frame(maxWidth: .infinity, minHeight: 150, alignment: .topLeading)
                .glassEffect(.regular.tint(.blue.opacity(0.15)), in: RoundedRectangle(cornerRadius: Theme.Radius.tile, style: .continuous))
                .accessibilityElement(children: .combine)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private struct Tile {
        let title: String
        let systemImage: String
        let value: String
        let detail: String?
    }

    private var tiles: [Tile] {
        let now = forecast.current
        var result: [Tile] = []
        if let feels = now.apparentTemperature {
            let note = abs(feels - now.temperature) < 1.5 ? "Similar to the actual temperature." : (feels < now.temperature ? "Wind makes it feel colder." : "Humidity makes it feel warmer.")
            result.append(Tile(title: "Feels Like", systemImage: "thermometer.medium", value: units.temperatureText(feels), detail: note))
        }
        if let humidity = now.humidity {
            result.append(Tile(title: "Humidity", systemImage: "humidity", value: "\(Int((humidity * 100).rounded()))%", detail: nil))
        }
        if let wind = now.windSpeed {
            let gust = now.windGust.map { "Gusts to \(units.windText($0))" }
            let direction = now.windDirection.map { "From the \(Self.compass($0))" }
            result.append(Tile(title: "Wind", systemImage: "wind", value: units.windText(wind), detail: [direction, gust].compactMap { $0 }.joined(separator: ". ")))
        }
        if let uv = now.uvIndex ?? forecast.today?.uvIndexMax {
            result.append(Tile(title: "UV Index", systemImage: "sun.max.fill", value: "\(Int(uv.rounded()))", detail: Self.uvCategory(uv)))
        }
        if let today = forecast.today, let sunrise = today.sunrise, let sunset = today.sunset {
            let showSunset = Date() > sunrise && Date() < sunset
            result.append(Tile(title: showSunset ? "Sunset" : "Sunrise", systemImage: showSunset ? "sunset.fill" : "sunrise.fill",
                               value: time(showSunset ? sunset : sunrise), detail: showSunset ? "Sunrise \(time(sunrise))" : "Sunset \(time(sunset))"))
        }
        if let pressure = now.pressure {
            let value = units.usesUSUnits() ? (pressure * 0.02953).formatted(.number.precision(.fractionLength(2))) + " inHg" : "\(Int(pressure.rounded())) hPa"
            result.append(Tile(title: "Pressure", systemImage: "gauge.with.dots.needle.33percent", value: value, detail: nil))
        }
        return result
    }

    private func time(_ date: Date) -> String {
        var style = Date.FormatStyle(date: .omitted, time: .shortened)
        style.timeZone = forecast.timeZone
        return date.formatted(style)
    }

    static func compass(_ degrees: Double) -> String {
        let names = ["north", "northeast", "east", "southeast", "south", "southwest", "west", "northwest"]
        let index = Int(((degrees.truncatingRemainder(dividingBy: 360) + 360).truncatingRemainder(dividingBy: 360) + 22.5) / 45) % 8
        return names[index]
    }

    static func uvCategory(_ value: Double) -> String {
        switch value {
        case ..<3: "Low"
        case ..<6: "Moderate"
        case ..<8: "High"
        case ..<11: "Very High"
        default: "Extreme"
        }
    }
}
