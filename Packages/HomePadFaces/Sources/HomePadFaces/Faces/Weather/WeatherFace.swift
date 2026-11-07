import HomePadCore
import HomePadUI
import SwiftUI

/// `faces.weather`: an animated sky for the current condition and time of
/// day. From across the room it shows the place, a big temperature and a
/// small time in the corner. Up close the temperature glances smaller and
/// moves up as the next hours fade in (HomeView's far and near views). The
/// place, the temperature and the time are one view at both distances, so
/// they glide between them.
///
/// It shows the iPad's own weather, or a city chosen in the editor, with the
/// sky and the time of that city.
struct WeatherFace: View {
    static let style = FaceOption.style([
        FaceChoice("animated", "Animated", systemImage: "cloud.sun.rain"),
        FaceChoice("still", "Still", systemImage: "cloud.sun"),
    ], cardStyle: .symbol)
    /// The city whose weather shows. Empty is the household's own location.
    static let place = FaceOption(
        id: "place", title: "City",
        kind: .slots([FaceSlot(id: "place", title: "City", automaticTitle: "Current Location")], .cities),
        note: "Current Location follows the location in Weather settings."
    )

    static let definition = FaceDefinition(
        id: "faces.weather", title: "Weather", summary: "A living sky with the temperature you can read from anywhere",
        systemImage: "cloud.sun", sortOrder: 20, options: [style, place],
        widgets: .besideWidgets()
    ) { WeatherFace() }

    /// How often a chosen city's weather is asked for again. The service
    /// caches it for as long, like the household's own weather.
    static let cityRefresh: Duration = .seconds(30 * 60)

    @Environment(\.faceInsets) private var faceInsets
    @Environment(\.faceKeepClear) private var keepClear
    @Environment(\.faceProfileZone) private var profileZone

    @Environment(\.faceConfiguration) private var configuration
    @Environment(\.displayCondition) private var condition
    @Environment(\.isThumbnail) private var isThumbnail
    @Environment(\.proximity) private var proximity
    @Environment(AppServices.self) private var services
    /// The chosen city's weather, once fetched.
    @State private var cityWeather: CityWeather?

    var body: some View {
        let city = configuration.slot(Self.place.id).flatMap(WorldCity.city)
        let weather = city.map { city in cityWeather?.cityID == city.id ? cityWeather?.snapshot : nil } ?? services.weather.current
        let isNight = condition == .night
        let calendar = Self.calendar(for: city)
        FaceTimeline(.minute) { date in
            let sky = skyCondition(weather)
            let time = skyTime(weather, at: date, calendar: calendar)
            ZStack {
                if isNight {
                    Color.black.ignoresSafeArea()
                } else {
                    SkyView(condition: sky, time: time,
                            isAnimated: configuration.value(Self.style) == "animated" && !isThumbnail)
                        .id(sky)
                    // Keeps the white text readable on a bright sky. It leaves
                    // with the text behind the Home Screen.
                    SkyTextShade(condition: sky, time: time)
                        .faceForeground()
                }
                // Behind the Home Screen the sky is all there is.
                content(weather, placeName: city?.name, date: date, timeZone: calendar.timeZone, isNight: isNight)
                    .faceForeground()
            }
            // Glass widgets read the sky: light over a bright day, dark at night.
            .backdropTone(isNight ? .black : SkyPalette.tone(sky, time))
        }
        .task(id: TaskKey(cityID: city?.id, isSleeping: condition == .sleeping)) {
            guard let city else {
                await services.weather.refresh()
                return
            }
            // Nothing is fetched while the display sleeps under its black cover.
            guard condition != .sleeping else { return }
            while !Task.isCancelled {
                if let snapshot = await services.weather.snapshot(for: city.weatherLocation) {
                    cityWeather = CityWeather(cityID: city.id, snapshot: snapshot)
                }
                try? await Task.sleep(for: Self.cityRefresh)
            }
        }
        // While a chosen city's weather has not come in yet.
        .faceIsLoading(city != nil && cityWeather?.cityID != city?.id && condition != .sleeping)
    }

    private struct TaskKey: Hashable {
        var cityID: String?
        var isSleeping: Bool
    }

    private struct CityWeather {
        var cityID: String
        var snapshot: WeatherSnapshot
    }

    /// The calendar for the face's clock and sky: the city's time zone, or the iPad's.
    private static func calendar(for city: WorldCity?) -> Calendar {
        var calendar = Calendar.current
        if let city { calendar.timeZone = city.timeZone }
        return calendar
    }

    private func skyCondition(_ weather: WeatherSnapshot?) -> SkyCondition {
        if let override = FaceDebugOptions.weatherOverride, let sky = SkyCondition.from(debugName: override) { return sky }
        guard let weather else { return .partlyCloudy }
        return SkyCondition.from(symbolName: weather.symbolName, conditionText: weather.conditionText)
    }

    private func skyTime(_ weather: WeatherSnapshot?, at date: Date, calendar: Calendar) -> SkyTime {
        SkyTime.at(date, sunrise: weather?.sunrise, sunset: weather?.sunset, isDaylight: weather?.isDaylight,
                   symbolName: weather?.symbolName ?? "", calendar: calendar)
    }

    /// The place and the temperature, centered, with the time in the top
    /// trailing corner at every distance, as on HomeView. Up close the next
    /// hours fade in below them.
    /// - Parameter timeZone: The zone the time and hours read in: a chosen city's own.
    private func content(_ weather: WeatherSnapshot?, placeName: String?, date: Date, timeZone: TimeZone,
                         isNight: Bool) -> some View {
        let isNear = proximity >= .mid
        return GeometryReader { proxy in
            // Sized for the room clear of the widgets and the Now Playing pill.
            let area = proxy.size.leaving(keepClear)
            let side = min(area.width, area.height)
            let timeSpot = Self.timeSpot(size: proxy.size, insets: faceInsets, profileZone: profileZone)
            ZStack(alignment: .topTrailing) {
                VStack(spacing: Theme.Spacing.l) {
                    headline(weather, placeName: placeName, side: side, temperatureScale: isNear ? 0.24 : 0.36,
                             isNight: isNight)
                        .frame(maxHeight: .infinity)
                    if isNear, let weather,
                       case let hours = DemoForecast.hours(for: weather, service: services.weather, now: date),
                       !hours.isEmpty {
                        HourlyStrip(hours: hours, palette: isNight ? .night : nil, timeZone: timeZone)
                            .transition(.proximityDetail)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(faceInsets)
                // One view at both distances, a little larger from across the
                // room. Its size animates. In the corner, it leaves the headline
                // centered.
                // Text applies the environment's zone to a format, so it is set there.
                Text(date, format: .dateTime.hour().minute())
                    .environment(\.timeZone, timeZone)
                    .displayFont(side * (isNear ? Self.nearTimeShare : Self.farTimeShare), weight: .semibold)
                    .lineLimit(1)
                    .foregroundStyle(ink(isNight))
                    .flattenedShadow(color: .black.opacity(isNight ? 0 : 0.18), radius: 12, y: 4)
                    .frame(height: timeSpot.height)
                    .padding(.top, timeSpot.top)
                    .padding(.trailing, timeSpot.trailing)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    /// Where the time sits, from the face's top and trailing edges.
    struct TimeSpot: Equatable {
        var top: CGFloat
        var trailing: CGFloat
        /// The row it is centered in, or nil for its own height.
        var height: CGFloat?
    }

    /// The time goes in the top trailing corner of the room the face keeps,
    /// as on HomeView. Where the profile button sits in that corner, the time
    /// sits just before the button, on its center line.
    static func timeSpot(size: CGSize, insets: EdgeInsets, profileZone zone: CGRect) -> TimeSpot {
        let corner = CGPoint(x: size.width - insets.trailing, y: insets.top)
        guard !zone.isNull, zone.contains(corner) else {
            return TimeSpot(top: insets.top, trailing: insets.trailing, height: nil)
        }
        let button = Theme.Size.profileButton
        return TimeSpot(top: zone.maxY - FaceGrid.gap - button, trailing: size.width - zone.minX, height: button)
    }

    /// The time's font size from across the room and up close, as a share of
    /// the shorter side of the room the face keeps.
    static let farTimeShare: CGFloat = 0.055
    static let nearTimeShare: CGFloat = 0.04

    /// - Parameter placeName: The chosen city, named even before its weather arrives.
    private func headline(_ weather: WeatherSnapshot?, placeName: String?, side: CGFloat, temperatureScale: CGFloat,
                          isNight: Bool) -> some View {
        // Each line casts its own shadow: the glass temperature must not be
        // flattened, or it could not see the sky behind it.
        let shadow = Color.black.opacity(isNight ? 0 : 0.18)
        return VStack(spacing: side * 0.008) {
            Text(placeName ?? weather?.locationName ?? "Weather")
                .font(.display(side * 0.065, weight: .semibold))
                .flattenedShadow(color: shadow, radius: 12, y: 4)
            temperature(weather, size: side * temperatureScale, isNight: isNight)
            if let weather {
                Text(weather.conditionText)
                    .font(.display(side * 0.045, weight: .medium))
                    .flattenedShadow(color: shadow, radius: 12, y: 4)
                if let high = weather.high, let low = weather.low {
                    Text("H:\(Int(high.rounded()))°  L:\(Int(low.rounded()))°")
                        .font(.display(side * 0.045, weight: .medium))
                        .flattenedShadow(color: shadow, radius: 12, y: 4)
                }
            }
        }
        .foregroundStyle(ink(isNight))
    }

    /// The big temperature: frosted glass over the sky like HomeView's, or
    /// red at night. Its size animates, so walking up shrinks it smoothly and
    /// the lines around it move with it.
    @ViewBuilder
    private func temperature(_ weather: WeatherSnapshot?, size: CGFloat, isNight: Bool) -> some View {
        let text = weather.map { "\(Int($0.temperature.rounded()))°" } ?? "--"
        if isNight {
            Text(text)
                .displayFont(size, weight: .light)
        } else {
            let line = GlyphLine(text, font: Self.temperatureFont)
            GlassNumerals(line: line, tint: .white)
                .frame(width: line.advance * size, height: line.lineHeight * size)
                .accessibilityElement()
                .accessibilityLabel(text)
        }
    }

    /// The glass temperature's font, SF Rounded. Its outlines scale to their frame.
    private static let temperatureFont: UIFont = {
        let font = UIFont.systemFont(ofSize: 100, weight: .regular)
        return font.fontDescriptor.withDesign(.rounded).map { UIFont(descriptor: $0, size: 100) } ?? font
    }()

    private func ink(_ isNight: Bool) -> Color {
        isNight ? FacePalette.night.ink : .white
    }
}

extension SkyCondition {
    /// Parses a debug launch argument such as "rain" or "partlyCloudy".
    static func from(debugName: String) -> SkyCondition? {
        SkyCondition(rawValue: debugName) ?? allCases.first { $0.rawValue.lowercased() == debugName.lowercased() }
    }
}
