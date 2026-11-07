import Foundation
import HomePadCore

/// Setting keys owned by the Personal module, named `personal.<area>.<setting>`.
public enum PersonalSettings {
    /// Show demo calendars, reminders and photos instead of the
    /// iPad's own data. On by default in the simulator, which has no accounts.
    public static let demoData = SettingKey<Bool>("personal.demoData", default: isSimulator)

    // MARK: Calendar and reminders

    /// Explicit audience per calendar or reminder list identifier.
    /// Identifiers are per device, so this does not sync through iCloud.
    public static let calendarAudiences = SettingKey<[String: CalendarAudience]>("personal.calendar.audiences", default: [:])
    public static let unassignedCalendars = SettingKey<UnassignedCalendarPolicy>("personal.calendar.unassigned", default: .admins)
    /// Calendars each person unchecked in the Calendar app's Calendars list,
    /// keyed by member identifier, or "guest" while nobody is selected. Only
    /// unchecked ones are saved, so calendars added later show. Separate from
    /// `calendarAudiences`, which decides who may see a calendar at all.
    public static let uncheckedCalendars = SettingKey<[String: Set<String>]>("personal.calendar.unchecked", default: [:])
    /// Reminders list that new items go to when no list is named. Other modules
    /// add groceries by name, so this is a title rather than an identifier.
    public static let defaultReminderList = SettingKey<String>("personal.reminders.defaultList", default: "Groceries", syncsWithICloud: true)

    // MARK: Weather

    public static let weatherLocation = SettingKey<WeatherLocationChoice>("personal.weather.location", default: .undecided)
    public static let weatherUnits = SettingKey<WeatherUnitSystem>("personal.weather.units", default: .automatic, syncsWithICloud: true)
    /// Minutes between automatic refreshes.
    public static let weatherRefreshMinutes = SettingKey<Int>("personal.weather.refreshMinutes", default: 30)

    // MARK: World clock

    public static let worldClockCities = SettingKey<[WorldClockCity]>("personal.worldclock.cities", default: WorldClockCity.defaults, syncsWithICloud: true)
    public static let worldClockStyle = SettingKey<WorldClockStyle>("personal.worldclock.style", default: .analog, syncsWithICloud: true)

    // MARK: Photos

    public static let photoSources = SettingKey<PhotoSourceSelection>("personal.photos.sources", default: PhotoSourceSelection())
    /// Seconds each photo stays up in the slideshow and the Photo widget.
    public static let slideshowInterval = SettingKey<Double>("personal.photos.slideshowInterval", default: 8)

    // MARK: Find My

    /// Whose each tracked device is, by tracked device ID, as an admin chose in
    /// Personal Info. Devices left out are matched to members automatically.
    public static let findMyOwners = SettingKey<[String: FindMyOwnerChoice]>("personal.findmy.owners", default: [:])
    /// Every recognized member sees every member's devices, as Family Sharing
    /// does. Off means each person sees their own, and admins see all.
    public static let findMyShareWithEveryone = SettingKey<Bool>("personal.findmy.shareWithEveryone", default: false)

    static var isSimulator: Bool {
        #if targetEnvironment(simulator)
        true
        #else
        false
        #endif
    }
}
