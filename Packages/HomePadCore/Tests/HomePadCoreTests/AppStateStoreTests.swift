import Foundation
import Testing
@testable import HomePadCore

/// Apps reopen where they were left: values persist, stay apart per person,
/// fall back to defaults, go stale by the time rule, and give way to launch
/// arguments and explicit requests.
@MainActor @Suite struct AppStateStoreTests {
    private enum Mode: String, Codable, Sendable { case day, week, month }

    private let mode = AppStateKey("calendar.mode", default: Mode.day, scope: .member)
    private let room = AppStateKey<String?>("home.room", default: nil)
    private let date = AppStateKey("calendar.date", default: Date(timeIntervalSince1970: 0), scope: .member, lifetime: .timePosition)
    private let scroll = AppStateKey<String?>("photos.top", default: nil, scope: .member, storage: .session)

    @MainActor private struct Fixture {
        let defaults: UserDefaults
        let settings: SettingsStore
        let household: Household
        let store: AppStateStore
        let kyle: HouseholdMember
        let sam: HouseholdMember

        /// A second store over the same saved data, as after a relaunch.
        func relaunched() -> AppStateStore {
            let settings = SettingsStore(defaults: defaults)
            return AppStateStore(settings: settings, household: household)
        }
    }

    private func makeFixture() -> Fixture {
        let defaults = UserDefaults(suiteName: "test.appstate.\(UUID())")!
        let settings = SettingsStore(defaults: defaults)
        let household = Household(store: settings)
        let kyle = HouseholdMember(name: "Kyle", isAdmin: true)
        let sam = HouseholdMember(name: "Sam")
        household.add(kyle)
        household.add(sam)
        return Fixture(defaults: defaults, settings: settings, household: household,
                       store: AppStateStore(settings: settings, household: household), kyle: kyle, sam: sam)
    }

    // MARK: Persistence

    @Test func persistentValuesSurviveARelaunch() {
        let fixture = makeFixture()
        fixture.store[room] = "Kitchen"
        #expect(fixture.store[room] == "Kitchen")
        #expect(fixture.relaunched()[room] == "Kitchen")
    }

    @Test func sessionValuesLastOnlyForTheLaunch() {
        let fixture = makeFixture()
        fixture.store[scroll] = "photo-40"
        #expect(fixture.store[scroll] == "photo-40")
        #expect(fixture.relaunched()[scroll] == nil)
    }

    @Test func resetGoesBackToTheDefault() {
        let fixture = makeFixture()
        fixture.store[room] = "Kitchen"
        fixture.store.reset(room)
        #expect(fixture.store[room] == nil)
        #expect(fixture.relaunched()[room] == nil)
    }

    /// Bindings write on every redraw. Writing what is saved must not touch
    /// UserDefaults or redraw every view that reads a setting.
    @Test func writingTheSavedValueAgainDoesNothing() {
        let fixture = makeFixture()
        fixture.store[room] = "Kitchen"
        let revision = fixture.settings.revision
        fixture.store[room] = "Kitchen"
        #expect(fixture.settings.revision == revision)
        fixture.store[room] = "Porch"
        #expect(fixture.settings.revision == revision + 1)
    }

    // MARK: Per person

    @Test func memberStateIsKeptForEachRecognizedPerson() {
        let fixture = makeFixture()
        let store = fixture.store
        fixture.household.recognize(fixture.kyle.id)
        store[mode] = .week
        fixture.household.recognize(fixture.sam.id)
        #expect(store[mode] == .day, "Sam never chose a view, so Calendar opens on Day for them")
        store[mode] = .month
        fixture.household.recognize(fixture.kyle.id)
        #expect(store[mode] == .week)
        fixture.household.signOut()
        #expect(store[mode] == .day, "guests never see a member's choice")
    }

    /// Picking someone by hand does not unlock their personal content, so it
    /// does not open their state either.
    @Test func aMemberPickedByHandSharesTheGuestState() {
        let fixture = makeFixture()
        fixture.household.recognize(fixture.kyle.id)
        fixture.store[mode] = .week
        fixture.household.signOut()
        fixture.store[mode] = .month
        fixture.household.select(fixture.kyle.id)
        #expect(fixture.store[mode] == .month)
        #expect(fixture.store.owner(for: .member) == "guest")
    }

    @Test func householdStateIsSharedByEveryone() {
        let fixture = makeFixture()
        fixture.household.recognize(fixture.kyle.id)
        fixture.store[room] = "Kitchen"
        fixture.household.recognize(fixture.sam.id)
        #expect(fixture.store[room] == "Kitchen")
        fixture.household.signOut()
        #expect(fixture.store[room] == "Kitchen")
    }

    // MARK: Fallbacks

    @Test func nothingSavedReadsAsTheDefault() {
        let fixture = makeFixture()
        #expect(fixture.store.savedValue(mode) == nil)
        #expect(fixture.store[mode] == .day)
    }

    @Test func undecodableSavedDataReadsAsTheDefault() {
        let fixture = makeFixture()
        fixture.defaults.set(Data("not json".utf8), forKey: fixture.store.storageName(for: mode))
        #expect(fixture.relaunched()[mode] == .day)
    }

    /// A view hands out one default per opening, so `Date()` stays the same
    /// instant while the app is open, and a nil default stays nil.
    @Test func aViewKeepsOneDefaultPerOpening() {
        let today = AppStateKey("calendar.date", default: Date())
        let visit = AppStateVisit()
        let first = visit.defaultValue(for: today)
        #expect(visit.defaultValue(for: today) == first)
        let optional = AppStateKey<String?>("x", default: nil)
        #expect(AppStateVisit().defaultValue(for: optional) == nil)
    }

    // MARK: Staleness

    @Test func timePositionsLastAFewHoursOnTheSameDay() {
        let calendar = Calendar(identifier: .gregorian)
        let morning = calendar.date(from: DateComponents(year: 2026, month: 10, day: 21, hour: 9))!
        #expect(AppStateStore.isFresh(savedAt: morning, openedAt: morning.addingTimeInterval(60), calendar: calendar))
        #expect(AppStateStore.isFresh(savedAt: morning, openedAt: morning.addingTimeInterval(3.5 * 3600), calendar: calendar))
        #expect(!AppStateStore.isFresh(savedAt: morning, openedAt: morning.addingTimeInterval(AppStateStore.timePositionLifetime), calendar: calendar))
        let lateNight = calendar.date(from: DateComponents(year: 2026, month: 10, day: 21, hour: 23, minute: 30))!
        #expect(!AppStateStore.isFresh(savedAt: lateNight, openedAt: lateNight.addingTimeInterval(3600), calendar: calendar),
                "after midnight the app opens on the new day")
    }

    /// 9 a.m. today in the store's calendar, so a few hours later is still
    /// the same day whenever the tests run. From `Date()`, a run after 9 p.m.
    /// crossed midnight and failed.
    private var morning: Date {
        Calendar.current.date(bySettingHour: 9, minute: 0, second: 0, of: Date())!
    }

    @Test func aStaleDateFallsBackToTheDefaultButKeepsTheMode() {
        let fixture = makeFixture()
        let store = fixture.store
        let saved = morning
        let nextWeek = saved.addingTimeInterval(7 * 86_400)
        store.set(nextWeek, for: date, now: saved)
        store[mode] = .week
        #expect(store.savedValue(date, openedAt: saved.addingTimeInterval(600)) == nextWeek)
        #expect(store.savedValue(date, openedAt: saved.addingTimeInterval(2 * 86_400)) == nil, "two days later Calendar opens on today")
        #expect(store[mode] == .week, "configuration never goes stale")
    }

    /// Writing the same date again keeps the time it was chosen, so a view
    /// redrawing never keeps an old date fresh.
    @Test func rewritingATimePositionKeepsWhenItWasChosen() {
        let fixture = makeFixture()
        let chosen = morning
        let day = chosen.addingTimeInterval(86_400)
        fixture.store.set(day, for: date, now: chosen)
        fixture.store.set(day, for: date, now: chosen.addingTimeInterval(3 * 3600))
        #expect(fixture.store.savedValue(date, openedAt: chosen.addingTimeInterval(4.5 * 3600)) == nil)
    }

    // MARK: Requests and launch arguments

    /// An explicit request (a widget, the assistant, a launch argument) is
    /// assigned over the restored value, and the app reopens on it.
    @Test func anExplicitRequestReplacesTheRestoredValue() {
        let fixture = makeFixture()
        fixture.store[room] = "Kitchen"
        fixture.store[room] = "Garage"
        #expect(fixture.relaunched()[room] == "Garage")
    }

    /// Launches that open a screen start every app from its defaults and never
    /// change what the iPad saved.
    @Test func aFreshStartIgnoresAndKeepsWhatWasSaved() {
        let fixture = makeFixture()
        fixture.household.recognize(fixture.kyle.id)
        fixture.store[mode] = .week
        fixture.store[room] = "Kitchen"
        let launched = fixture.relaunched()
        launched.startFresh()
        #expect(launched[mode] == .day)
        #expect(launched[room] == nil)
        launched[room] = "Porch"
        #expect(launched[room] == "Porch", "state still carries from one opening to the next in this launch")
        #expect(fixture.relaunched()[room] == "Kitchen")
        #expect(fixture.relaunched()[mode] == .week)
    }
}
