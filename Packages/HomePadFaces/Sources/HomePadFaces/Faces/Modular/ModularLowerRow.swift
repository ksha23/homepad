import HomePadCore
import HomePadUI
import SwiftUI

/// The lower half of the Modular face. By default, today's events beside the
/// weather. With nothing left to list it shows one short line over a wider
/// weather block with the next few hours, so the space never sits empty. The
/// editor can show only the events or only the forecast instead.
struct ModularLowerRow: View {
    /// What the row shows, chosen in the editor.
    enum Content: String {
        case eventsAndForecast = "both"
        case events
        case forecast
    }

    let date: Date
    let events: [CalendarItem]
    let weather: WeatherSnapshot?
    let hours: [WeatherSnapshot.Hour]
    let palette: FacePalette
    let layout: ModularLayout
    var content = Content.eventsAndForecast

    var body: some View {
        let row = layout.lower
        let hasAgenda = EventsList.hasAgenda(events, after: date)
        switch content {
        case .eventsAndForecast where hasAgenda:
            // Events get the larger share: titles need the width, and the
            // temperature scales down to fit what is left.
            let (leading, trailing) = layout.split(row, leadingFraction: 0.58)
            HStack(alignment: .top, spacing: layout.gap) {
                EventsList(events: events, now: date, maxRows: 8, palette: palette, fontSize: layout.textSize)
                    .frame(width: leading.width, height: leading.height, alignment: .topLeading)
                WeatherSummary(weather: weather, palette: palette,
                               temperatureSize: WeatherSummary.temperatureSize(fitting: trailing.size))
                    .frame(width: trailing.width, height: trailing.height, alignment: .topLeading)
            }
        case .eventsAndForecast:
            let hintHeight = layout.textSize * 1.5
            VStack(alignment: .leading, spacing: layout.gap * 0.5) {
                EventsHint(palette: palette, fontSize: layout.textSize)
                    .frame(height: hintHeight, alignment: .leading)
                forecast(in: CGSize(width: row.width, height: row.height - hintHeight - layout.gap * 0.5))
            }
        case .events where hasAgenda:
            // The whole row for the day, in larger type.
            EventsList(events: events, now: date, maxRows: 8, palette: palette, fontSize: layout.textSize * 1.2)
                .frame(width: row.width, height: row.height, alignment: .topLeading)
        case .events:
            EventsHint(palette: palette, fontSize: layout.textSize * 1.4)
                .frame(width: row.width, height: row.height, alignment: .topLeading)
        case .forecast:
            forecast(in: row.size)
        }
    }

    /// The temperature with the next few hours beside it, sized to `block`.
    private func forecast(in block: CGSize) -> some View {
        let temperature = min(WeatherSummary.temperatureSize(fitting: block), block.width * 0.2)
        // The forecast follows the temperature as one group. Pinned to the
        // trailing edge it left a wide hole on the full-width far layout.
        return HStack(alignment: .top, spacing: layout.gap * 2.5) {
            WeatherSummary(weather: weather, palette: palette, temperatureSize: temperature)
                .fixedSize()
            ModularForecast(hours: hours, palette: palette, size: temperature * 0.24)
        }
        .frame(width: block.width, height: block.height, alignment: .topLeading)
    }
}

/// The next few hours as columns of hour, symbol and temperature, drawn in
/// the face's own colors.
struct ModularForecast: View {
    let hours: [WeatherSnapshot.Hour]
    let palette: FacePalette
    /// Size of the hour labels. Symbols and temperatures scale from it.
    let size: CGFloat

    var body: some View {
        ViewThatFits(in: .horizontal) {
            columns(5)
            columns(4)
            columns(3)
            EmptyView()
        }
    }

    private func columns(_ count: Int) -> some View {
        HStack(alignment: .top, spacing: size * 1.2) {
            ForEach(Array(hours.prefix(count).enumerated()), id: \.offset) { index, hour in
                VStack(spacing: size * 0.6) {
                    Text(index == 0 ? "Now" : hour.date.formatted(.dateTime.hour()))
                        .font(.display(size * 0.85, weight: .semibold))
                        .foregroundStyle(palette.secondary)
                    Image(systemName: hour.symbolName)
                        .symbolRenderingMode(palette.isNight ? .monochrome : .multicolor)
                        .font(.display(size * 1.5))
                        .foregroundStyle(palette.ink)
                        .frame(height: size * 1.9)
                    Text("\(Int(hour.temperature.rounded()))°")
                        .font(.display(size * 1.1, weight: .semibold))
                        .foregroundStyle(palette.ink)
                        .monospacedDigit()
                }
                .lineLimit(1)
                .fixedSize()
            }
        }
    }
}
