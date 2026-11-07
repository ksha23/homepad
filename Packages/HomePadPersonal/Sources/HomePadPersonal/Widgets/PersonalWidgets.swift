import HomePadCore
import HomePadUI
import SwiftUI

/// Widgets for the Home Screen and the Modular face. Each one draws its own
/// tile and fills whatever frame the host gives it. Up Next and Reminders are
/// personal: the host hides them until a member is recognized, and the
/// content is also filtered by the calendar privacy policy. Up Next and
/// Reminders also come tall, where they list more.
@MainActor
enum PersonalWidgets {
    /// The sizes of the widgets whose extra height lists more.
    static let listSizes: [WidgetSize] = [.small, .medium, .large, .tall]

    static func register(in registry: ModuleRegistry, personal: PersonalServices) {
        // Rain or snow on the way asks a widget stack to show the weather.
        registry.register(widget: WidgetDescriptor(id: "personal.weather", title: "Weather", systemImage: "cloud.sun.fill", opensApp: "weather",
                                                   relevance: { PersonalWidgetRelevance.weather(personal.weather.forecast, now: $0.date) }) { size in
            WeatherWidgetView(size: size).personalEnvironment(personal)
        })
        // The half hour before an event and the event itself ask a widget stack to show Up Next.
        registry.register(widget: WidgetDescriptor(id: "personal.upnext", title: "Up Next", systemImage: "calendar",
                                                   supportedSizes: listSizes, isPersonal: true, opensApp: "calendar",
                                                   relevance: { PersonalWidgetRelevance.upNext(personal.calendar, now: $0.date) }) { size in
            UpNextWidgetView(size: size).personalEnvironment(personal)
        })
        // Edit Widget picks the list.
        registry.register(widget: WidgetDescriptor(id: "personal.reminders", title: "Reminders", systemImage: "checklist",
                                                   supportedSizes: listSizes, isPersonal: true, opensApp: "reminders") { size in
            RemindersWidgetView(size: size).personalEnvironment(personal)
        } settings: { settings in
            RemindersWidgetSettingsView(settings: settings).personalEnvironment(personal)
        })
        registry.register(widget: WidgetDescriptor(id: "personal.worldclock", title: "World Clock", systemImage: "globe", opensApp: "worldclock") { size in
            WorldClockWidgetView(size: size).personalEnvironment(personal)
        })
        registry.register(widget: WidgetDescriptor(id: "personal.photo", title: "Photo", systemImage: "photo.fill", opensApp: "photos") { size in
            PhotoWidgetView(size: size).personalEnvironment(personal)
        })
        registry.register(widget: WidgetDescriptor(id: "personal.date", title: "Date", systemImage: "calendar.day.timeline.left", opensApp: "calendar") { size in
            DateWidgetView(size: size)
        })
    }
}
