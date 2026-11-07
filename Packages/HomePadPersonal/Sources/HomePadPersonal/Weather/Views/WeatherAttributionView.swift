import HomePadUI
import SwiftUI

/// Credits the forecast's source, as WeatherKit and Open-Meteo both require.
struct WeatherAttributionView: View {
    @Environment(PersonalWeatherService.self) private var weather

    var body: some View {
        if let attribution = weather.attribution, let forecast = weather.forecast {
            VStack(spacing: Theme.Spacing.xs) {
                if let url = attribution.url {
                    Link(attribution.name, destination: url).font(.callout.weight(.semibold))
                } else {
                    Text(attribution.name).font(.callout.weight(.semibold))
                }
                Text("Updated \(forecast.fetchedAt.formatted(.relative(presentation: .named)))")
                    .font(.caption)
            }
            .foregroundStyle(.secondary)
            .padding(.vertical, Theme.Spacing.m)
        }
    }
}
