import HomePadCore
import HomePadUI
import SwiftUI

/// Weather on a sky tile: now, then hours (medium) and days (large).
struct WeatherWidgetView: View {
    @Environment(PersonalWeatherService.self) private var weather
    let size: WidgetSize

    var body: some View {
        if let forecast = weather.forecast {
            content(forecast)
                // A new reading rolls in and the symbol turns into the next one.
                .animation(Theme.Motion.standard, value: forecast.current.temperature)
                .animation(Theme.Motion.standard, value: forecast.current.condition.symbolName(isDaylight: forecast.current.isDaylight))
                .padding(Theme.Spacing.m)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .foregroundStyle(.white)
                .background {
                    WeatherSkyBackground(condition: forecast.current.condition, isDaylight: forecast.current.isDaylight, isAnimated: false)
                        .overlay { textShade(forecast.current) }
                }
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.tile, style: .continuous))
                .nightModeAware()
        } else {
            GlassTile {
                Label("Weather", systemImage: "cloud.sun.fill").font(.headline)
                Spacer()
                Text("Open Weather to choose a location.").font(.callout).foregroundStyle(.secondary)
            }
            .task { await weather.refreshIfStale() }
        }
    }

    /// A shade between the sky and the white text, as dark as
    /// `WeatherPalette.textShade` works out from the sky's own colors: none
    /// on a dark sky, and just enough on a bright one for the text to read.
    @ViewBuilder
    private func textShade(_ current: CurrentConditions) -> some View {
        let shade = WeatherPalette.textShade(for: current.condition, isDaylight: current.isDaylight)
        if shade.contains(where: { $0 > 0 }) {
            LinearGradient(colors: shade.map { Color.black.opacity($0) }, startPoint: .top, endPoint: .bottom)
                .allowsHitTesting(false)
        }
    }

    /// How much the widget shows. Tiles differ in height between iPads and text
    /// sizes, so the widget drops rows until it fits instead of overflowing.
    private enum Detail {
        /// Small: condition and high/low. Medium: hours. Large: hours and days.
        case full
        /// Medium and large: hours under a one-row header, for short tiles.
        case compact
        /// Small: high/low. Large: hours.
        case reduced
        /// Place and temperature, with high/low on small.
        case minimal
    }

    private func content(_ forecast: WeatherForecast) -> some View {
        ViewThatFits(in: .vertical) {
            layout(forecast, detail: .full)
            if size != .small { compactLayout(forecast) }
            layout(forecast, detail: .reduced)
            layout(forecast, detail: .minimal)
        }
    }

    private func layout(_ forecast: WeatherForecast, detail: Detail) -> some View {
        let units = weather.units
        let symbol = forecast.current.condition.symbolName(isDaylight: forecast.current.isDaylight)
        return VStack(alignment: .leading, spacing: size == .large ? Theme.Spacing.s : 0) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 0) {
                    Text(forecast.place.name).font(.headline).lineLimit(1)
                    Text(units.temperatureText(forecast.current.temperature)).font(.display(size == .large ? 60 : 44, weight: .light))
                        .contentTransition(.numericText(value: forecast.current.temperature))
                }
                Spacer(minLength: 0)
                if size == .small {
                    conditionSymbol(symbol, font: .title2)
                } else {
                    VStack(alignment: .trailing, spacing: 2) {
                        conditionSymbol(symbol, font: .title2)
                        Text(forecast.current.condition.text).font(.subheadline.weight(.semibold))
                        highLow(forecast, units: units)
                    }
                }
            }
            if size == .small {
                Spacer(minLength: 0)
                if detail == .full {
                    Text(forecast.current.condition.text).font(.subheadline.weight(.semibold)).lineLimit(1)
                }
                highLow(forecast, units: units)
            } else {
                Spacer(minLength: 0)
                if detail == .full || (size == .large && detail == .reduced) {
                    hours(forecast, units: units)
                }
                if size == .large && detail == .full {
                    Divider().overlay(.white.opacity(0.3))
                    days(forecast, units: units)
                }
            }
        }
    }

    /// Temperature, place and condition on one row, with the hours below.
    private func compactLayout(_ forecast: WeatherForecast) -> some View {
        let units = weather.units
        return VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            HStack(alignment: .center, spacing: Theme.Spacing.s) {
                Text(units.temperatureText(forecast.current.temperature)).font(.display(34, weight: .light))
                    .contentTransition(.numericText(value: forecast.current.temperature))
                VStack(alignment: .leading, spacing: 0) {
                    Text(forecast.place.name).font(.headline).lineLimit(1)
                    Text(forecast.current.condition.text).font(.subheadline.weight(.semibold)).lineLimit(1)
                }
                Spacer(minLength: 0)
                VStack(alignment: .trailing, spacing: 0) {
                    conditionSymbol(forecast.current.condition.symbolName(isDaylight: forecast.current.isDaylight), font: .title3)
                    highLow(forecast, units: units)
                }
            }
            Spacer(minLength: 0)
            hours(forecast, units: units)
        }
    }

    private func conditionSymbol(_ name: String, font: Font) -> some View {
        Image(systemName: name)
            .symbolRenderingMode(.multicolor)
            .font(font)
            .contentTransition(.symbolEffect(.replace))
    }

    private func highLow(_ forecast: WeatherForecast, units: WeatherUnitSystem) -> some View {
        Text(forecast.today.map { "H:\(units.temperatureText($0.high))  L:\(units.temperatureText($0.low))" } ?? "")
            .font(.subheadline.weight(.semibold))
    }

    private func hours(_ forecast: WeatherForecast, units: WeatherUnitSystem) -> some View {
        // Ticks on the hour so a finished hour leaves between forecast refreshes.
        ClockTimeline(every: .hour) { now in
            HStack {
                ForEach(Array(forecast.upcomingHours(at: now).prefix(6).enumerated()), id: \.element.id) { index, hour in
                    VStack(spacing: 2) {
                        Text(index == 0 ? "Now" : hour.date.formatted(.dateTime.hour())).font(.subheadline.weight(.semibold))
                        Image(systemName: hour.condition.symbolName(isDaylight: hour.isDaylight)).symbolRenderingMode(.multicolor)
                        Text(units.temperatureText(hour.temperature)).font(.subheadline.weight(.semibold))
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
    }

    private func days(_ forecast: WeatherForecast, units: WeatherUnitSystem) -> some View {
        VStack(spacing: Theme.Spacing.xs) {
            ForEach(Array(forecast.daily.prefix(5).enumerated()), id: \.element.id) { index, day in
                HStack {
                    Text(index == 0 ? "Today" : day.date.formatted(.dateTime.weekday(.abbreviated)))
                        .font(.subheadline.weight(.semibold)).frame(width: 60, alignment: .leading)
                    Image(systemName: day.condition.symbolName()).symbolRenderingMode(.multicolor).frame(width: 30)
                    Spacer()
                    Text(units.temperatureText(day.low)).foregroundStyle(.secondary)
                    Text(units.temperatureText(day.high)).frame(width: 44, alignment: .trailing)
                }
                .font(.subheadline)
                .monospacedDigit()
            }
        }
    }
}
