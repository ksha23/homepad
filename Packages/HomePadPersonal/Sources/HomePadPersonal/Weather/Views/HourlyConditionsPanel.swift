import HomePadUI
import SwiftUI

/// The "Conditions" panel: the next 24 hours as temperature, chance of
/// precipitation or wind, switched with three glass icons.
struct HourlyConditionsPanel: View {
    enum Metric: String, CaseIterable, Identifiable {
        case temperature, precipitation, wind

        var id: String { rawValue }

        var systemImage: String {
            switch self {
            case .temperature: "cloud.sun.fill"
            case .precipitation: "drop.fill"
            case .wind: "wind"
            }
        }
    }

    let hours: [HourlyForecast]
    let units: WeatherUnitSystem
    @State private var metric: Metric = .temperature

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Conditions").font(.title.weight(.semibold))
                    Text(subtitle).font(.title3).foregroundStyle(.cyan)
                }
                Spacer()
                HStack(spacing: Theme.Spacing.xs) {
                    ForEach(Metric.allCases) { option in
                        Button {
                            withAnimation(Theme.Motion.standard) { metric = option }
                        } label: {
                            Image(systemName: option.systemImage)
                                .symbolRenderingMode(.multicolor)
                                .font(.title3)
                                .frame(width: 56, height: Theme.Size.minTapTarget)
                                .background(metric == option ? Color.white.opacity(0.22) : .clear, in: Capsule())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(option.rawValue.capitalized)
                    }
                }
                .padding(Theme.Spacing.xs)
                .background(.white.opacity(0.1), in: Capsule())
            }
            Spacer(minLength: Theme.Spacing.m)
            ScrollView(.horizontal) {
                HStack(spacing: Theme.Spacing.l) {
                    ForEach(Array(hours.prefix(25).enumerated()), id: \.element.id) { index, hour in
                        column(hour, isNow: index == 0)
                    }
                }
            }
            .scrollIndicators(.hidden)
            Spacer(minLength: 0)
        }
        .padding(Theme.Spacing.l)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .glassEffect(.regular.tint(.blue.opacity(0.15)), in: RoundedRectangle(cornerRadius: Theme.Radius.tile, style: .continuous))
    }

    private var subtitle: String {
        switch metric {
        case .temperature: "Temperature (\(units.temperatureUnit() == .fahrenheit ? "°F" : "°C"))"
        case .precipitation: "Chance of Precipitation"
        case .wind: "Wind Speed"
        }
    }

    private func column(_ hour: HourlyForecast, isNow: Bool) -> some View {
        VStack(spacing: Theme.Spacing.s) {
            Text(isNow ? "Now" : hour.date.formatted(.dateTime.hour()))
                .font(.title3.weight(.semibold))
            Image(systemName: hour.condition.symbolName(isDaylight: hour.isDaylight))
                .symbolRenderingMode(.multicolor)
                .font(.largeTitle)
                .frame(height: 44)
            Text(value(for: hour))
                .font(.title3.weight(.semibold))
                .monospacedDigit()
        }
        .frame(minWidth: 64)
        .accessibilityElement(children: .combine)
    }

    private func value(for hour: HourlyForecast) -> String {
        switch metric {
        case .temperature: units.temperatureText(hour.temperature)
        case .precipitation: hour.precipitationChance.map { "\(Int(($0 * 100).rounded()))%" } ?? "–"
        case .wind: hour.windSpeed.map { units.windText($0) } ?? "–"
        }
    }
}
