import Foundation
import HomePadCore

/// The Personal module's launch arguments, alongside the shell's
/// `-HomePadOpenApp`. All but the calendar report work in debug builds only,
/// for simulator screenshots:
///
///     -HomePadWeatherCity "Madison, WI"   use this city for weather (MapKit search)
///     -HomePadRecognize Kyle               recognize this member, adding them as an admin if needed
///     -HomePadCalendarMode week            open Calendar in the day, week or month view
///     -HomePadCalendarsList YES            open Calendar's Calendars list
///     -HomePadUncheckCalendars "Work"      leave exactly these calendars unchecked (comma separated titles,
///                                          or none) for whoever is active a second after launch
///     -HomePadSeedCalendars YES            simulator: turn demo data off and add real "Canvas" and
///                                          "Family" calendars (grant access first with
///                                          `xcrun simctl privacy <sim> grant calendar com.ksha23.homepad`)
///     -HomePadPhotosAlbum "Summer Trips"   open Photos on an album, by title or kind (library, favorites)
///     -HomePadPhotosSlideshow YES          start the Photos slideshow
///     -HomePadPhotosViewer 5               with -HomePadPhotosAlbum, open that album's fifth photo full screen
///     -HomePadFindMyDevice "Sam's iPhone"  open Find My on a device's card, by name or ID
///     -HomePadDemoWeekday 3                demo calendar: today follows this weekday's events (1 is
///                                          Sunday, 3 is the busy Tuesday with long Canvas titles)
///     -HomePadCalendarReport YES           write calendar-report.txt to Documents (works on a device too)
///     -HomePadPersonalGallery YES          debug: the personal.widgets and personal.settings apps
///
/// These are launch arguments, read from UserDefaults' argument domain. They
/// are not settings, so they do not go through `SettingsStore`.
@MainActor
enum PersonalDebugLaunch {
    /// The weekday (1 is Sunday) whose demo events today shows, from
    /// `-HomePadDemoWeekday`, so a screenshot can show a busy day on any date.
    /// Debug builds only.
    static var demoWeekday: Int? {
        #if DEBUG
        let weekday = UserDefaults.standard.integer(forKey: "HomePadDemoWeekday")
        return (1...7).contains(weekday) ? weekday : nil
        #else
        nil
        #endif
    }

    /// The Calendar view to open with, from `-HomePadCalendarMode`. Debug builds only.
    static var calendarMode: CalendarDisplayMode? {
        #if DEBUG
        UserDefaults.standard.string(forKey: "HomePadCalendarMode").flatMap(CalendarDisplayMode.init(rawValue:))
        #else
        nil
        #endif
    }

    /// Whether Calendar opens its Calendars list, from `-HomePadCalendarsList`. Debug builds only.
    static var showsCalendarsList: Bool {
        #if DEBUG
        UserDefaults.standard.bool(forKey: "HomePadCalendarsList")
        #else
        false
        #endif
    }

    /// The album Photos opens on, from `-HomePadPhotosAlbum`. Debug builds only.
    static var photosAlbum: String? {
        #if DEBUG
        UserDefaults.standard.string(forKey: "HomePadPhotosAlbum").flatMap { $0.isEmpty ? nil : $0 }
        #else
        nil
        #endif
    }

    /// The photo Photos opens full screen in the album from `-HomePadPhotosAlbum`,
    /// as an index, from `-HomePadPhotosViewer` (1 is the first). Debug builds only.
    static var photosViewerIndex: Int? {
        #if DEBUG
        let number = UserDefaults.standard.integer(forKey: "HomePadPhotosViewer")
        return number > 0 ? number - 1 : nil
        #else
        nil
        #endif
    }

    /// Whether Photos starts its slideshow, from `-HomePadPhotosSlideshow`. Debug builds only.
    static var startsPhotosSlideshow: Bool {
        #if DEBUG
        UserDefaults.standard.bool(forKey: "HomePadPhotosSlideshow")
        #else
        false
        #endif
    }

    /// The device Find My opens on, from `-HomePadFindMyDevice`. Debug builds only.
    static var findMyDevice: String? {
        #if DEBUG
        UserDefaults.standard.string(forKey: "HomePadFindMyDevice").flatMap { $0.isEmpty ? nil : $0 }
        #else
        nil
        #endif
    }

    /// Whether to write the calendar report, from `-HomePadCalendarReport`.
    /// In every build, so it can be fetched from a device with `devicectl`.
    static var writesCalendarReport: Bool {
        UserDefaults.standard.bool(forKey: "HomePadCalendarReport")
    }

    /// Whether to register the widget and settings gallery apps, from
    /// `-HomePadPersonalGallery`. Debug builds only.
    static var showsGallery: Bool {
        #if DEBUG
        UserDefaults.standard.bool(forKey: "HomePadPersonalGallery")
        #else
        false
        #endif
    }

    static func apply(services: AppServices, weather: PersonalWeatherService, calendar: HouseholdCalendarService) {
        #if DEBUG
        let defaults = UserDefaults.standard
        #if targetEnvironment(simulator)
        if defaults.bool(forKey: "HomePadSeedCalendars") {
            services.settings[PersonalSettings.demoData] = false
            calendar.eventKitBackend?.seedSimulatorCalendars()
        }
        #endif
        if let name = defaults.string(forKey: "HomePadRecognize"), !name.isEmpty {
            let household = services.household
            if let member = household.members.first(where: { $0.name == name }) {
                household.recognize(member.id)
            } else {
                let member = HouseholdMember(name: name, avatar: String(name.prefix(1)), isAdmin: true)
                if household.add(member) { household.recognize(member.id) }
            }
            household.unlockWindow = 24 * 3600
        }
        if let list = defaults.string(forKey: "HomePadUncheckCalendars"), !list.isEmpty {
            let titles = Set(list.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) })
            Task { @MainActor in
                // After the shell applies -HomePadMember, so the choice is that member's.
                try? await Task.sleep(for: .seconds(1))
                calendar.showAll()
                for source in calendar.visibleCalendars where titles.contains(source.title) {
                    calendar.setShown(false, for: source)
                }
            }
        }
        if let city = defaults.string(forKey: "HomePadWeatherCity"), !city.isEmpty {
            Task {
                if let place = await PlaceSearch.search(city).first?.place { await weather.choose(place) }
            }
        }
        #endif
    }
}
