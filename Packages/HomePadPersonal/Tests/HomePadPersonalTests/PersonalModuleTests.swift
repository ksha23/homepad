import Foundation
import HomePadCore
import Testing
@testable import HomePadPersonal

@MainActor
@Suite struct PersonalModuleTests {
    @Test func moduleHasID() {
        #expect(PersonalModule.id == "personal")
    }

    @Test func registersServicesAppsWidgetsPaneAndTools() {
        let services = AppServices(settings: SettingsStore(defaults: UserDefaults(suiteName: "homepad.personal.module.\(UUID().uuidString)")!))
        let registry = ModuleRegistry()
        PersonalModule.register(services: services, registry: registry)

        #expect(services.calendar is HouseholdCalendarService)
        #expect(services.weather is PersonalWeatherService)
        #expect(Set(registry.apps.map(\.id)).isSuperset(of: ["calendar", "reminders", "weather", "worldclock", "photos", "findmy"]))
        #expect(registry.settingsPanes.contains { $0.id == "personal" && $0.adminOnly })

        let personalWidgets = Set(registry.widgets.filter(\.isPersonal).map(\.id))
        #expect(personalWidgets == ["personal.upnext", "personal.reminders"])
        #expect(registry.widgets.count >= 6)

        let tools = Dictionary(uniqueKeysWithValues: registry.tools.map { ($0.name, $0) })
        #expect(tools["get_daily_forecast"]?.requiresRecognizedMember == false)
        #expect(tools["list_reminders"]?.requiresRecognizedMember == true)
        #expect(tools["complete_reminder"]?.requiresRecognizedMember == true)
        #expect(tools["world_time"] != nil)
        #expect(tools["find_device"]?.requiresRecognizedMember == true)
        #expect(tools["play_sound_on_device"]?.requiresRecognizedMember == true)
        #expect(tools["get_weather"] == nil)
    }

    @Test func worldTimeToolAnswersOffline() async throws {
        let services = AppServices(settings: SettingsStore(defaults: UserDefaults(suiteName: "homepad.personal.tool.\(UUID().uuidString)")!))
        let registry = ModuleRegistry()
        PersonalModule.register(services: services, registry: registry)
        let tool = try #require(registry.tools.first { $0.name == "world_time" })
        let answer = try await tool.handler(["city": "Tokyo"])
        #expect(answer.contains("Tokyo"))
    }
}
