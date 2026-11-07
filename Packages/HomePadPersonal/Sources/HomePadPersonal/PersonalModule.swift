import HomePadCore
import HomePadUI
import SwiftUI

/// Calendar, reminders, weather, photos, clocks and Find My.
///
/// Installs `services.calendar` and `services.weather`, and registers the
/// personal apps, widgets, the Personal Info settings pane, assistant tools
/// and background tasks (photo sync, calendars and reminders, weather).
public enum PersonalModule: HomePadModule {
    public static let id = "personal"

    public static func register(services: AppServices, registry: ModuleRegistry) {
        let personal = PersonalServices(services: services)
        services.calendar = personal.calendar
        services.weather = personal.weather
        PersonalMemberMove.register(services: services)
        PersonalApps.register(in: registry, personal: personal)
        PersonalWidgets.register(in: registry, personal: personal)
        registry.register(settings: SettingsPaneDescriptor(id: "personal", title: "Personal Info", systemImage: "person.text.rectangle",
                                                           tint: .red, sortOrder: 40, adminOnly: true) {
            PersonalSettingsPane().personalEnvironment(personal)
        })
        registry.register(tools: PersonalTools.make(personal: personal))
        registry.register(tools: FindMyTools.make(findMy: personal.findMy))
        PersonalBackgroundTasks.register(in: services.backgroundWork, personal: personal)
        PersonalScreenContext.register(in: registry, focus: personal.screen) { [weak services] in
            services?.photoAccess ?? PhotoAccessPolicy(ownerID: nil, viewerID: nil)
        }
        #if DEBUG
        PersonalDebugGallery.register(in: registry, personal: personal)
        #endif
    }

    public static func didFinishLaunching(services: AppServices, registry: ModuleRegistry) {
        guard let weather = services.weather as? PersonalWeatherService,
              let calendar = services.calendar as? HouseholdCalendarService else { return }
        Task { await calendar.ensureDefaultList() }
        PersonalDebugLaunch.apply(services: services, weather: weather, calendar: calendar)
    }
}
