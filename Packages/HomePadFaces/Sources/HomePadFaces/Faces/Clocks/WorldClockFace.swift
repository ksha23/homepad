import HomePadCore
import HomePadUI
import SwiftUI

/// `faces.worldclock`: several cities at a glance. Each dial turns dark
/// when it is night there. From across the room each city is a big dial (or
/// big digits) and its name. Up close the dials glance smaller and each
/// city's time and its offset from here fade in under them.
struct WorldClockFace: View {
    static let style = FaceOption.style([
        FaceChoice("analog", "Analog", systemImage: "clock"),
        FaceChoice("digital", "Digital", systemImage: "textformat.123"),
    ])
    static let cities = FaceOption(
        id: "cities", title: "Cities",
        kind: .slots((1...6).map { FaceSlot(id: "city\($0)", title: "City \($0)") }, .cities)
    )
    static let defaultCities = ["new-york", "london", "paris", "tokyo", "sydney", "honolulu"]

    static let definition = FaceDefinition(
        id: "faces.worldclock", title: "World Clock", summary: "The time in the cities you care about",
        systemImage: "globe", sortOrder: 44, options: [style, cities],
        widgets: .besideWidgets()
    ) { WorldClockFace() }

    @Environment(\.faceInsets) private var faceInsets
    @Environment(\.faceProfileZone) private var profileZone

    @Environment(\.faceConfiguration) private var configuration
    @Environment(\.displayCondition) private var condition
    @Environment(\.proximity) private var proximity

    var body: some View {
        let palette = FacePalette.resolve(.graphite, condition: condition)
        let cities = Self.chosenCities(configuration)
        let isAnalog = configuration.value(Self.style) == "analog"
        FaceTimeline(.minute) { date in
            GeometryReader { proxy in
                // The room inside the insets, which keep clear of the widgets, the
                // Now Playing pill and the profile button, so every row fits its
                // height as well as its width.
                let insets = faceInsets.clearing(profileZone, in: proxy.size)
                let area = CGSize(width: max(proxy.size.width - insets.leading - insets.trailing, 1),
                                  height: max(proxy.size.height - insets.top - insets.bottom, 1))
                let grid = GridMath.dimensions(count: cities.count, in: area, cellAspect: isAnalog ? 0.85 : 1.6)
                let columns = Array(repeating: GridItem(.flexible(), spacing: Theme.Spacing.l), count: grid.columns)
                let cellHeight = (area.height - Theme.Spacing.l * CGFloat(grid.rows - 1)) / CGFloat(grid.rows)
                ZStack {
                    Rectangle().fill(palette.background).ignoresSafeArea()
                    LazyVGrid(columns: columns, spacing: Theme.Spacing.l) {
                        ForEach(cities) { city in
                            CityClock(city: city, date: date, isAnalog: isAnalog, palette: palette, showsDetail: proximity >= .mid)
                                .frame(height: cellHeight)
                        }
                    }
                    .padding(insets)
                }
            }
        }
        .faceBackdrop(tone: palette.tone) { palette.background.ignoresSafeArea() }
    }

    /// The cities in the configuration's slots, in slot order, or the defaults.
    static func chosenCities(_ configuration: FaceConfiguration) -> [WorldCity] {
        let ids = (1...6).map { configuration.slots["city\($0)"] ?? defaultCities[$0 - 1] }
        return ids.compactMap { $0.isEmpty ? nil : WorldCity.city($0) }
    }
}

/// One city: a dial (or digits) and its name, and up close its time and its
/// offset from here. The dial's frame and the type sizes animate, so the
/// city glides between the two.
private struct CityClock: View {
    let city: WorldCity
    let date: Date
    let isAnalog: Bool
    let palette: FacePalette
    let showsDetail: Bool

    var body: some View {
        GeometryReader { proxy in
            // The dial (or the digits) gives up height to the lines that fade in under it.
            let dialSide = min(proxy.size.width, proxy.size.height * (showsDetail ? 0.66 : 0.82))
            let digits = min(proxy.size.width / 4.6, proxy.size.height * (showsDetail ? 0.3 : 0.44))
            VStack(spacing: Theme.Spacing.s) {
                if isAnalog {
                    dial.frame(width: dialSide, height: dialSide)
                } else {
                    time
                        .displayFont(digits, weight: .semibold)
                        .monospacedDigit()
                        .lineLimit(1)
                        .foregroundStyle(palette.ink)
                        .frame(maxHeight: .infinity)
                }
                Text(city.name)
                    .displayFont(max(isAnalog ? dialSide * 0.1 : digits * 0.32, 18), weight: .semibold)
                    .foregroundStyle(palette.ink)
                if isAnalog, showsDetail {
                    time
                        .font(.display(max(dialSide * 0.08, 15), weight: .medium))
                        .monospacedDigit()
                        .foregroundStyle(palette.accent)
                        .transition(.proximityDetail)
                }
                if showsDetail {
                    Text(city.relativeLabel(from: .current, at: date))
                        .font(.display(max(dialSide * 0.07, 14), weight: .medium))
                        .foregroundStyle(palette.secondary)
                        .transition(.proximityDetail)
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
    }

    /// The city's own time. `Text` reads the zone from the environment, not
    /// from the format, so it is set there: with the format's zone alone every
    /// city showed the time here.
    private var time: some View {
        Text(date, format: .dateTime.hour().minute())
            .environment(\.timeZone, city.timeZone)
    }

    private var dial: some View {
        let colors: AnalogClock.Colors = palette.isNight
            ? AnalogClock.Colors(face: .black, ink: palette.ink, accent: palette.accent, rim: palette.secondary)
            : (city.isNight(at: date) ? .night : .day)
        return AnalogClock(date: date, timeZone: city.timeZone, colors: colors)
    }
}
