import Foundation
import HomePadCore
import SwiftUI
import Testing
@testable import HomePadAssistant

/// What is on screen reaches the system prompt, and personal screens stay out
/// until someone is recognized.
@MainActor
@Suite struct ScreenContextTests {
    private let registry = ModuleRegistry()

    init() {
        registry.register(app: AppDescriptor(id: "recipes", title: "Recipes", systemImage: "fork.knife", category: .kitchen) { EmptyView() })
        registry.register(app: AppDescriptor(id: "calendar", title: "Calendar", systemImage: "calendar", category: .productivity) { EmptyView() })
        registry.register(app: AppDescriptor(id: "findmy", title: "Find My", systemImage: "location", category: .communication,
                                             requiresRecognizedMember: true) { EmptyView() })
        registry.register(app: AppDescriptor(id: AssistantModule.appID, title: "Assistant", systemImage: "sparkles",
                                             category: .productivity) { EmptyView() })
        registry.register(screenContext: ScreenContextProvider(appID: "recipes") {
            "The recipe card for Shakshuka. Ingredients for 4 servings: 6 eggs; 1 onion."
        })
        registry.register(screenContext: ScreenContextProvider(appID: "calendar", isPersonal: true) {
            "The Day view of Thursday, October 22, 2026."
        })
        registry.register(screenContext: ScreenContextProvider(appID: "findmy") { "Alex's iPhone is selected." })
    }

    private func describe(_ appID: String?, unlocked: Bool) -> String? {
        ScreenContextReader.describe(visibleAppID: appID, registry: registry, isPersonalUnlocked: unlocked)
    }

    @Test func namesTheOpenAppAndWhatItShows() {
        #expect(describe("recipes", unlocked: false)
            == "The Recipes app. The recipe card for Shakshuka. Ingredients for 4 servings: 6 eggs; 1 onion.")
    }

    @Test func saysNothingOnAFaceTheHomeScreenOrInTheAssistantApp() {
        #expect(describe(nil, unlocked: true) == nil)
        #expect(describe(AssistantModule.appID, unlocked: true) == nil)
        #expect(describe("unknown", unlocked: true) == nil)
    }

    @Test func personalSummariesWaitForRecognition() {
        #expect(describe("calendar", unlocked: false) == "The Calendar app.")
        #expect(describe("calendar", unlocked: true) == "The Calendar app. The Day view of Thursday, October 22, 2026.")
    }

    @Test func appsThatNeedRecognitionSayNothingToGuests() {
        #expect(describe("findmy", unlocked: false) == nil)
        #expect(describe("findmy", unlocked: true) == "The Find My app. Alex's iPhone is selected.")
    }

    @Test func overlaysOverEveryScreenSpeakUpWhenTheyHaveSomethingToSay() {
        var ringing = false
        registry.register(screenContext: ScreenContextProvider(id: "doorbell", appID: nil) {
            ringing ? "The doorbell is ringing." : nil
        })
        #expect(describe(nil, unlocked: false) == nil)
        ringing = true
        #expect(describe(nil, unlocked: false) == "The doorbell is ringing.")
        #expect(describe("recipes", unlocked: false)?.hasSuffix("1 onion. The doorbell is ringing.") == true)
    }

    @Test func thePromptSaysWhatThisMeans() throws {
        let prompt = SystemPromptBuilder.build(try context(screen: describe("recipes", unlocked: false), compact: false))
        #expect(prompt.contains("On screen: The Recipes app. The recipe card for Shakshuka."))
        #expect(prompt.contains("this, these or here"))
        let none = SystemPromptBuilder.build(try context(screen: nil, compact: false))
        #expect(!none.contains("On screen"))
        #expect(!none.contains("this, these or here"))
    }

    @Test func theSmallModelGetsAShortScreenLine() throws {
        let long = String(repeating: "Ingredient; ", count: 200)
        let prompt = SystemPromptBuilder.build(try context(screen: long, compact: true))
        let line = try #require(prompt.components(separatedBy: "\n").first { $0.hasPrefix("On screen:") })
        #expect(line.count == SystemPromptBuilder.screenLimit(compact: true) + "On screen: ".count)
        #expect(line.hasSuffix("…"))
    }

    /// The runtime reads the app the shell says is open, follows recognition,
    /// and leaves the screen out of requests from other modules.
    @Test func theRuntimeDescribesTheVisibleApp() throws {
        let services = AppServices(settings: SettingsStore(defaults: try #require(UserDefaults(suiteName: "assistant.screen.\(UUID())"))))
        let runtime = AssistantRuntime(services: services, registry: registry, conversations: ConversationStore(directory: nil))
        let prompt = { (shown: Bool) in runtime.systemPrompt(for: ProviderCatalog.anthropic, tools: [], isShownHere: shown) }
        services.visibleAppID = "recipes"
        #expect(prompt(true).contains("On screen: The Recipes app. The recipe card for Shakshuka."))
        #expect(!prompt(false).contains("On screen"))
        services.visibleAppID = "calendar"
        #expect(prompt(true).contains("On screen: The Calendar app.\n"))
        let member = HouseholdMember(name: "Alex")
        _ = services.household.add(member)
        services.household.select(member.id)
        #expect(prompt(true).contains("On screen: The Calendar app.\n"), "picked by hand is not recognized")
        services.household.recognize(member.id)
        #expect(prompt(true).contains("On screen: The Calendar app. The Day view of Thursday, October 22, 2026."))
        services.visibleAppID = nil
        #expect(!prompt(true).contains("On screen"))
    }

    /// "Add these ingredients to my shopping list" on a recipe card is one call.
    @Test func addReminderTakesSeveralItems() async throws {
        let services = AppServices(settings: SettingsStore(defaults: try #require(UserDefaults(suiteName: "assistant.items.\(UUID())"))))
        let tool = PersonalTools.addReminder(ToolContext(services: services, registry: registry, confirmations: ConfirmationCenter()))
        #expect(tool.parameters["required"] == [])
        let reply = try await tool.handler(["items": ["6 eggs", "1 onion", " "], "list": "Groceries"])
        #expect(reply == "Added 2 items (6 eggs; 1 onion) to Groceries.")
        #expect(try await tool.handler(["title": "Call the plumber"]) == "Added reminder \"Call the plumber\".")
        await #expect(throws: ToolError.self) { try await tool.handler([:]) }
    }

    private func context(screen: String?, compact: Bool) throws -> PromptContext {
        PromptContext(
            now: Date(timeIntervalSince1970: 1_792_594_800), timeZone: try #require(TimeZone(identifier: "America/Chicago")),
            locationName: nil, weather: nil, memberName: nil, aboutMember: nil, isPersonalUnlocked: false,
            personality: .concise, homeLines: [], toolNames: [], compact: compact, screen: screen
        )
    }
}
