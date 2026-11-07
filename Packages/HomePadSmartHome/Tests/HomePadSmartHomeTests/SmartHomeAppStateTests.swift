import Foundation
import HomePadCore
import Testing
@testable import HomePadSmartHome

/// The Home and Dashboards apps reopen as they were left, for everyone in the
/// household, and their saved format keeps loading.
@MainActor @Suite("Smart home app state")
struct SmartHomeAppStateTests {
    @Test func theHomeIsTheHouseholdsSoItsStateIsShared() {
        #expect(SmartHomeAppState.room.scope == .household)
        #expect(SmartHomeAppState.accessory.scope == .household)
        #expect(SmartHomeAppState.camera.scope == .household)
        #expect(SmartHomeAppState.allCameras.scope == .household)
        #expect(SmartHomeAppState.dashboard.scope == .household)
    }

    @Test func aPickedRoomSurvivesARelaunch() {
        let defaults = UserDefaults(suiteName: "test.smarthome.appstate.\(UUID())")!
        let settings = SettingsStore(defaults: defaults)
        AppStateStore(settings: settings, household: Household(store: settings))[SmartHomeAppState.room] = "Kitchen"
        let relaunched = SettingsStore(defaults: defaults)
        #expect(AppStateStore(settings: relaunched, household: Household(store: relaunched))[SmartHomeAppState.room] == "Kitchen")
    }

    @Test func dashboardSelectionsRoundTrip() throws {
        for selection in [DashboardSelection.homeAssistant, .panel(UUID())] {
            let data = try JSONEncoder().encode(selection)
            #expect(try JSONDecoder().decode(DashboardSelection.self, from: data) == selection)
        }
    }
}
