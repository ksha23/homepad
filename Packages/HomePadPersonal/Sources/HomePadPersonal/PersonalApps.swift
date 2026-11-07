import HomePadCore
import HomePadUI
import SwiftUI

/// The Personal module's apps for the Home Screen grid.
@MainActor
enum PersonalApps {
    static func register(in registry: ModuleRegistry, personal: PersonalServices) {
        registry.register(app: AppDescriptor(id: "calendar", title: "Calendar", systemImage: "calendar", tint: .red,
                                             category: .productivity, sortOrder: 20) {
            CalendarAppView().personalEnvironment(personal)
        })
        registry.register(app: AppDescriptor(id: "reminders", title: "Reminders", systemImage: "checklist", tint: .orange,
                                             category: .productivity, sortOrder: 21) {
            RemindersAppView().personalEnvironment(personal)
        })
        registry.register(app: AppDescriptor(id: "weather", title: "Weather", systemImage: "cloud.sun.fill", tint: .blue,
                                             category: .productivity, sortOrder: 22) {
            WeatherAppView().personalEnvironment(personal)
        })
        registry.register(app: AppDescriptor(id: "worldclock", title: "World Clock", systemImage: "globe", tint: .indigo,
                                             category: .productivity, sortOrder: 23) {
            WorldClockAppView().personalEnvironment(personal)
        })
        // Personal: the library shows only to its owner and shared albums to
        // every recognized member (`PhotoAccessPolicy`), so a guest gets the gate.
        registry.register(app: AppDescriptor(id: "photos", title: "Photos", systemImage: "photo.on.rectangle.angled", tint: .pink,
                                             category: .media, sortOrder: 30, requiresRecognizedMember: true) {
            PhotosAppView().personalEnvironment(personal)
        })
        registry.register(app: AppDescriptor(id: "findmy", title: "Find My", systemImage: "location.circle.fill", tint: .green,
                                             category: .communication, sortOrder: 40, requiresRecognizedMember: true) {
            FindMyAppView().personalEnvironment(personal)
        })
    }
}
