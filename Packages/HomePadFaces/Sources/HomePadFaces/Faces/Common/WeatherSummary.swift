import HomePadCore
import HomePadUI
import SwiftUI

/// Location, a big temperature, the condition and the day's high and low,
/// the weather complication used by the Modular face.
struct WeatherSummary: View {
    let weather: WeatherSnapshot?
    let palette: FacePalette
    let temperatureSize: CGFloat

    /// The largest temperature size whose whole block fits in `size`.
    static func temperatureSize(fitting size: CGSize) -> CGFloat {
        min(size.height / 2.05, size.width / 2.1)
    }

    var body: some View {
        if let weather {
            VStack(alignment: .leading, spacing: temperatureSize * 0.06) {
                Label(weather.locationName, systemImage: "location.fill")
                    .labelStyle(.trailingIcon)
                    .font(.display(temperatureSize * 0.18, weight: .semibold))
                    .foregroundStyle(palette.accent)
                // As heavy as Modular's day number, so the two big facts match.
                Text("\(Int(weather.temperature.rounded()))°")
                    .font(.display(temperatureSize, weight: .bold))
                    .foregroundStyle(palette.ink)
                    .monospacedDigit()
                Label(weather.conditionText, systemImage: weather.symbolName)
                    .font(.display(temperatureSize * 0.17, weight: .semibold))
                    .foregroundStyle(palette.ink)
                    .symbolRenderingMode(palette.isNight ? .monochrome : .multicolor)
                if let high = weather.high, let low = weather.low {
                    Text("H:\(Int(high.rounded()))°  L:\(Int(low.rounded()))°")
                        .font(.display(temperatureSize * 0.16, weight: .medium))
                        .foregroundStyle(palette.secondary)
                }
            }
            .lineLimit(1)
            .minimumScaleFactor(0.6)
        } else {
            Label("Weather unavailable", systemImage: "cloud.fill")
                .font(.display(temperatureSize * 0.18, weight: .medium))
                .foregroundStyle(palette.secondary)
        }
    }
}
