import HomePadCore
import HomePadUI
import SwiftUI

/// Placeholder content for simulator screenshots (`-HomePadDemoContent YES`):
/// stand-in apps for every app ID other modules will register, a few widgets
/// and Control Center tiles, three people, and a playing song. Real
/// descriptors always win, since only missing IDs are filled in.
@MainActor
enum DemoContent {
    static func install(services: AppServices, registry: ModuleRegistry) {
        installApps(registry)
        installWidgets(registry)
        installControls(registry)
        installPeople(services.household)
        if let media = services.media as? NoopMediaService, media.nowPlaying == nil {
            media.nowPlaying = NowPlaying(title: "Morning Light", artist: "The Demo Band", isPlaying: true,
                                          outputName: "Kitchen")
        }
    }

    private static let apps: [(id: String, title: String, symbol: String, tint: Color, category: AppCategory, personal: Bool)] = [
        ("home", "Home", "house.fill", .orange, .home, false),
        ("music", "Music", "music.note", .pink, .media, false),
        ("calendar", "Calendar", "calendar", .red, .productivity, true),
        ("reminders", "Reminders", "checklist", .indigo, .productivity, true),
        ("weather", "Weather", "cloud.sun.fill", .cyan, .productivity, false),
        ("timers", "Timers", "timer", .orange, .kitchen, false),
        ("recipes", "Recipes", "fork.knife", .green, .kitchen, false),
        ("intercom", "Intercom", "waveform", .orange, .communication, false),
        ("photos", "Photos", "photo.on.rectangle", .purple, .media, false),
        ("worldclock", "World Clock", "globe", .gray, .productivity, false),
        ("mirror", "Mirror", "person.crop.square", .teal, .camera, false),
    ]

    private static func installApps(_ registry: ModuleRegistry) {
        for (index, app) in apps.enumerated() where registry.app(app.id) == nil {
            registry.register(app: AppDescriptor(
                id: app.id, title: app.title, systemImage: app.symbol, tint: app.tint, category: app.category,
                sortOrder: index * 10, requiresRecognizedMember: app.personal
            ) {
                AppScreen(app.title) {
                    EmptyStateView("Demo App", message: "The real \(app.title) app comes from its own module.",
                                   systemImage: app.symbol)
                }
            })
        }
    }

    private static func installWidgets(_ registry: ModuleRegistry) {
        guard registry.widgets.isEmpty else { return }
        registry.register(widget: WidgetDescriptor(id: "demo.weather", title: "Weather", systemImage: "cloud.sun.fill") { size in
            DemoWeatherWidget(size: size)
        })
        registry.register(widget: WidgetDescriptor(
            id: "demo.calendar", title: "Calendar", systemImage: "calendar", supportedSizes: [.medium, .large], isPersonal: true
        ) { _ in
            DemoCalendarWidget()
        })
        registry.register(widget: WidgetDescriptor(
            id: "demo.music", title: "Music", systemImage: "music.note", supportedSizes: [.small, .medium]
        ) { _ in
            DemoMusicWidget()
        })
    }

    private static func installControls(_ registry: ModuleRegistry) {
        guard registry.controls.isEmpty else { return }
        registry.register(control: ControlDescriptor(id: "demo.frontDoor", title: "Front Door") {
            DemoLockTile(name: "Front Door")
        })
        registry.register(control: ControlDescriptor(id: "demo.backDoor", title: "Back Yard Door") {
            DemoLockTile(name: "Back Yard Door")
        })
    }

    private static func installPeople(_ household: Household) {
        guard household.members.isEmpty else { return }
        household.add(HouseholdMember(name: "Alex", avatar: "🦊", colorHex: "#0A84FF", isAdmin: true, hasFaceEnrollment: true))
        household.add(HouseholdMember(name: "Sam", avatar: "🐼", colorHex: "#FF9F0A"))
        household.add(HouseholdMember(name: "Jordan", avatar: "🚀", colorHex: "#30D158"))
    }
}
