import HomePadUI
import SwiftUI

/// Weather up close: the place and temperature, the hourly Conditions panel,
/// the 10-day forecast and detail tiles. The app's header holds the place button. In landscape the header and hours sit
/// beside the 10-day forecast, with the details in a row of tiles below.
/// In portrait the details sit beside the 10-day forecast where two columns
/// of tiles fit, and below it in a row of three where they do not.
struct WeatherNearView: View {
    let forecast: WeatherForecast
    let units: WeatherUnitSystem

    /// Narrower than this, a tile's title breaks mid-word ("Hu-midity").
    private static let detailTileMinWidth: CGFloat = 200

    var body: some View {
        GeometryReader { proxy in
            ScrollView {
                Group {
                    if proxy.size.width > proxy.size.height * 1.2 {
                        wide(width: proxy.size.width)
                    } else {
                        tall(width: proxy.size.width)
                    }
                }
                .padding(.bottom, Theme.Spacing.l)
            }
            .scrollIndicators(.hidden)
        }
        .foregroundStyle(.white)
    }

    private func tall(width: CGFloat) -> some View {
        let besideWidth = width - DailyForecastPanel.minimumWidth - Theme.Spacing.l
        let fitsBeside = besideWidth >= Self.detailTileMinWidth * 2 + Theme.Spacing.m
        return VStack(spacing: Theme.Spacing.l) {
            header
            HourlyConditionsPanel(hours: forecast.upcomingHours(at: Date()), units: units)
            if fitsBeside {
                HStack(alignment: .top, spacing: Theme.Spacing.l) {
                    daily
                    WeatherDetailGrid(forecast: forecast, units: units)
                }
            } else {
                daily
                WeatherDetailGrid(forecast: forecast, units: units, columns: 3)
            }
            WeatherAttributionView()
        }
        .frame(maxWidth: 1100)
        .frame(maxWidth: .infinity)
    }

    private func wide(width: CGFloat) -> some View {
        VStack(spacing: Theme.Spacing.l) {
            WeatherWideTopLayout(spacing: Theme.Spacing.l) {
                header
                HourlyConditionsPanel(hours: forecast.upcomingHours(at: Date()), units: units)
                daily
            }
            WeatherDetailGrid(forecast: forecast, units: units, columns: 3)
            WeatherAttributionView()
        }
    }

    private var daily: some View {
        DailyForecastPanel(days: forecast.daily, current: forecast.current.temperature, units: units, timeZone: forecast.timeZone)
    }

    private var header: some View {
        VStack(spacing: Theme.Spacing.xs) {
            Text(forecast.place.name).font(.largeTitle.weight(.semibold))
            Text(units.temperatureText(forecast.current.temperature))
                .font(.display(120, weight: .thin))
                .contentTransition(.numericText(value: forecast.current.temperature))
                .animation(Theme.Motion.standard, value: forecast.current.temperature)
            Text(forecast.current.condition.text).font(.title.weight(.medium))
            if let today = forecast.today {
                Text("H:\(units.temperatureText(today.high))  L:\(units.temperatureText(today.low))")
                    .font(.title.weight(.medium))
            }
        }
        .frame(maxWidth: .infinity)
        // Drawn once. A live shadow was drawn again on every frame of the
        // moving sky and of every scroll.
        .wallpaperLabelShadow()
        .accessibilityElement(children: .combine)
    }
}
