import HomePadCore
import SwiftUI

/// The Personal module's own services, created once in `register`.
/// Apps, widgets and the settings pane get them through the environment
/// with `.personalEnvironment(_:)`.
@MainActor
final class PersonalServices {
    let calendar: HouseholdCalendarService
    let weather: PersonalWeatherService
    let photos: PhotoLibraryService
    let clocks: WorldClockStore
    let findMy: FindMyService
    /// What Calendar and Photos show, for the assistant.
    let screen = PersonalScreenFocus()

    init(services: AppServices) {
        calendar = HouseholdCalendarService(household: services.household, settings: services.settings) { [weak services] in
            services?.phoneCalendars
        }
        weather = PersonalWeatherService(settings: services.settings)
        photos = PhotoLibraryService(settings: services.settings, household: services.household)
        clocks = WorldClockStore(settings: services.settings)
        findMy = FindMyService(services: services)
    }
}

extension View {
    /// Injects the Personal module's services for its views.
    func personalEnvironment(_ personal: PersonalServices) -> some View {
        environment(personal.calendar)
            .environment(personal.weather)
            .environment(personal.photos)
            .environment(personal.clocks)
            .environment(personal.findMy)
            .environment(personal.screen)
    }
}
