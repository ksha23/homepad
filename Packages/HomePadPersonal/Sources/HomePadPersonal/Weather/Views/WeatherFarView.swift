import HomePadUI
import SwiftUI

/// Weather from across the room: city, a huge temperature, conditions, high and low.
struct WeatherFarView: View {
    let forecast: WeatherForecast
    let units: WeatherUnitSystem

    var body: some View {
        VStack(spacing: Theme.Spacing.s) {
            Text(forecast.place.name)
                .font(.farTitle)
            Text(units.temperatureText(forecast.current.temperature))
                .font(.display(260, weight: .thin))
                .contentTransition(.numericText(value: forecast.current.temperature))
                .animation(Theme.Motion.standard, value: forecast.current.temperature)
            Text(forecast.current.condition.text)
                .font(.farDetail)
            if let today = forecast.today {
                Text("H:\(units.temperatureText(today.high))  L:\(units.temperatureText(today.low))")
                    .font(.farDetail)
            }
        }
        .foregroundStyle(.white)
        // Drawn once. A live shadow was drawn again on every frame of the moving sky.
        .wallpaperLabelShadow()
        .multilineTextAlignment(.center)
        .minimumScaleFactor(0.5)
        .padding(Theme.Spacing.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
    }
}
