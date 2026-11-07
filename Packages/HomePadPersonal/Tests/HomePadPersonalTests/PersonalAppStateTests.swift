import Foundation
import HomePadCore
import MapKit
import Testing
@testable import HomePadPersonal

/// What the Personal apps reopen on: per person, falling back when a list is
/// gone or hidden, and the places Weather and World Clock already keep.
@MainActor @Suite struct PersonalAppStateTests {
    private let groceries = CalendarSource(id: "list.groceries", title: "Groceries", colorHex: "#34C759", kind: .reminders)
    private let work = CalendarSource(id: "list.work", title: "Work", colorHex: "#0A84FF", kind: .reminders)

    private func makeSettings() -> (SettingsStore, UserDefaults) {
        let defaults = UserDefaults(suiteName: "test.personal.appstate.\(UUID())")!
        return (SettingsStore(defaults: defaults), defaults)
    }

    @Test func personalAppsKeepTheirStatePerPerson() {
        #expect(PersonalAppState.calendarMode.scope == .member)
        #expect(PersonalAppState.calendarDate.scope == .member)
        #expect(PersonalAppState.reminderList.scope == .member)
        #expect(PersonalAppState.photosAlbum.scope == .member)
        #expect(PersonalAppState.photosGridTop.scope == .member)
        #expect(PersonalAppState.findMyDevice.scope == .member)
        #expect(PersonalAppState.findMyRegion.scope == .member)
    }

    @Test func calendarsDateGoesStaleButItsViewDoesNot() {
        #expect(PersonalAppState.calendarDate.lifetime == .timePosition)
        #expect(PersonalAppState.calendarMode.lifetime == .always)
        #expect(PersonalAppState.calendarMode.storage == .persistent)
        #expect(PersonalAppState.photosGridTop.storage == .session, "scroll positions stay in memory")
    }

    /// Kyle's list stays Kyle's: Sam and guests open on their own choice.
    @Test func aChosenListNeverShowsForSomeoneElse() {
        let (settings, _) = makeSettings()
        let household = Household(store: settings)
        let kyle = HouseholdMember(name: "Kyle")
        let sam = HouseholdMember(name: "Sam")
        household.add(kyle)
        household.add(sam)
        let store = AppStateStore(settings: settings, household: household)
        household.recognize(kyle.id)
        store[PersonalAppState.reminderList] = ReminderSelection(.list(work))
        household.recognize(sam.id)
        #expect(store[PersonalAppState.reminderList] == nil)
        household.signOut()
        #expect(store[PersonalAppState.reminderList] == nil)
        household.recognize(kyle.id)
        #expect(store[PersonalAppState.reminderList] == .list(id: work.id))
    }

    @Test func aSavedListShowsOnlyWhileItIsVisible() {
        let saved = ReminderSelection(.list(work))
        #expect(saved.filter(visibleLists: [groceries, work]) == .list(work))
        #expect(saved.filter(visibleLists: [groceries]) == nil, "a hidden or deleted list falls back to the default")
        #expect(ReminderSelection(.today).filter(visibleLists: []) == .today)
        #expect(ReminderSelection(.all).filter(visibleLists: []) == .all)
    }

    /// The stored format must keep loading on iPads that saved it.
    @Test func reminderSelectionsRoundTrip() throws {
        for selection in [ReminderSelection.today, .scheduled, .all, .list(id: "list.groceries")] {
            let data = try JSONEncoder().encode(selection)
            #expect(try JSONDecoder().decode(ReminderSelection.self, from: data) == selection)
        }
    }

    @Test func findMyMapRegionRoundTrips() {
        let region = MKCoordinateRegion(center: CLLocationCoordinate2D(latitude: 43.07, longitude: -89.4),
                                        span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.08))
        let saved = FindMyMapRegion(region)
        #expect(saved.region.center.latitude == 43.07)
        #expect(saved.region.span.longitudeDelta == 0.08)
    }

    /// World Clock already keeps its style in settings.
    @Test func worldClockStyleSurvivesARelaunch() {
        let (settings, defaults) = makeSettings()
        WorldClockStore(settings: settings).style = .digital
        #expect(WorldClockStore(settings: SettingsStore(defaults: defaults)).style == .digital)
    }

    /// Weather already keeps the place it shows in settings.
    @Test func weatherPlaceSurvivesARelaunch() {
        let (settings, defaults) = makeSettings()
        let madison = WeatherPlace(name: "Madison, WI", latitude: 43.07, longitude: -89.4)
        settings[PersonalSettings.weatherLocation] = .place(madison)
        let relaunched = PersonalWeatherService(settings: SettingsStore(defaults: defaults))
        #expect(relaunched.locationChoice == .place(madison))
    }
}
