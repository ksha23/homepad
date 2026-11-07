import HomePadCore
import HomePadUI
import SwiftUI

/// `faces.modular`: the information face. Date, a clock, the weather, the
/// day's events (personal ones only for a recognized member, shared
/// calendars for everyone) and widgets from other modules.
///
/// From across the room it is the date and the clock, filling the space
/// beside the widgets. Walking up, they glide into the top half and the
/// events and the weather fade in. Widgets show at every distance, in the
/// face's widget area: a column of two cells on the trailing side in
/// landscape, like the iPad's widget column, and two rows along the bottom in
/// portrait. The face's old widget slots become medium widgets there.
///
/// `ModularLayout` sizes every part from the screen, so the face fills an 11
/// or 13 inch iPad in either orientation and never runs off the edge.
struct ModularFace: View {
    static let style = FaceOption.style([
        FaceChoice("analog", "Analog", systemImage: "clock"),
        FaceChoice("digital", "Digital", systemImage: "textformat.123"),
    ])
    static let color = FaceOption.color([.ocean, .sage, .sand, .lavender, .coral, .porcelain, .graphite, .midnight], default: .ocean)
    /// What the panel under the clock shows.
    static let details = FaceOption(id: "details", title: "Details", kind: .choices([
        FaceChoice(ModularLowerRow.Content.eventsAndForecast.rawValue, "Events and Forecast", systemImage: "rectangle.split.2x1"),
        FaceChoice(ModularLowerRow.Content.events.rawValue, "Events", systemImage: "calendar"),
        FaceChoice(ModularLowerRow.Content.forecast.rawValue, "Forecast", systemImage: "cloud.sun"),
    ]), defaultValue: ModularLowerRow.Content.eventsAndForecast.rawValue)

    static let definition = FaceDefinition(
        id: "faces.modular", title: "Modular", summary: "Date, time, weather, your day and widgets",
        systemImage: "square.grid.2x2", sortOrder: 1, options: [style, color, details],
        widgets: .besideWidgets(legacySize: .medium)
    ) { ModularFace() }

    @Environment(\.faceInsets) private var faceInsets

    @Environment(\.faceConfiguration) private var configuration
    @Environment(\.displayCondition) private var condition
    @Environment(\.proximity) private var proximity
    @Environment(\.facesShowPersonal) private var showPersonal
    @Environment(AppServices.self) private var services
    @State private var events = TodayEvents()

    var body: some View {
        let palette = FacePalette.resolve(configuration.colors(Self.color), condition: condition)
        let isNear = proximity >= .mid
        let isDigital = configuration.value(Self.style) == "digital"
        let details = ModularLowerRow.Content(rawValue: configuration.value(Self.details)) ?? .eventsAndForecast
        // The face changes once a minute. Only the clock ticks every second up
        // close, so the events list (which measures several layouts to fit) and
        // the weather are not laid out again every second.
        FaceTimeline(.minute) { date in
            GeometryReader { proxy in
                let layout = ModularLayout(size: proxy.size, insets: faceInsets)
                let visible = events.visible(showPersonal: showPersonal)
                ZStack(alignment: .topLeading) {
                    FaceTimeline(isNear ? .second : .minute) { clockDate in
                        ModularHero(date: clockDate, isDigital: isDigital, showsSeconds: isNear, palette: palette,
                                    far: layout.heroLayout(isDigital: isDigital, isNear: false),
                                    near: layout.heroLayout(isDigital: isDigital, isNear: true), isNear: isNear)
                    }
                    // The detail, up close only. It fades in as the hero makes room
                    // (the host's `Theme.Motion.proximity`).
                    if isNear {
                        ModularLowerRow(
                            date: date, events: visible, weather: services.weather.current,
                            hours: hours(at: date), palette: palette, layout: layout, content: details
                        )
                        .offset(x: layout.lower.minX, y: layout.lower.minY)
                        .transition(.proximityDetail)
                    }
                }
                .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
                // Recognition unlocking the calendar fades the personal events in.
                .animation(.smooth(duration: 0.5), value: showPersonal)
            }
            .background(palette.background.ignoresSafeArea())
        }
        .task(id: "\(showPersonal)|\(services.calendar.reloadKey)") {
            while !Task.isCancelled {
                await events.refresh(calendar: services.calendar)
                try? await Task.sleep(for: .seconds(15 * 60))
            }
        }
        .faceBackdrop(tone: palette.tone) { palette.background.ignoresSafeArea() }
        .faceIsLoading(!events.hasLoaded)
    }

    private func hours(at date: Date) -> [WeatherSnapshot.Hour] {
        guard let weather = services.weather.current else { return [] }
        return DemoForecast.hours(for: weather, service: services.weather, now: date)
    }
}
