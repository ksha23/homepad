import Foundation
import FoundationModels
import HomePadCore
import Testing
@testable import HomePadAssistant

@MainActor
@Suite struct SupportTests {
    @Test func parsesFlexibleDates() throws {
        let zone = try #require(TimeZone(identifier: "America/Chicago"))
        let withZone = try #require(FlexibleDateParser.parse("2026-10-21T15:00:00Z"))
        #expect(withZone.timeIntervalSince1970 == 1_792_594_800)
        let local = try #require(FlexibleDateParser.parse("2026-10-21T10:00", timeZone: zone))
        #expect(local == withZone)
        #expect(FlexibleDateParser.parse("2026-10-21", timeZone: zone) != nil)
        #expect(FlexibleDateParser.parse("tomorrow") == nil)
    }

    @Test func convertsEveryToolSchemaForTheOnDeviceModel() throws {
        let services = AppServices.preview()
        let context = ToolContext(services: services, registry: ModuleRegistry(), confirmations: ConfirmationCenter())
        for tool in AssistantToolset.make(context) {
            _ = try JSONSchemaConverter.generationSchema(for: tool.parameters, name: tool.name)
        }
    }

    @Test func toolNamesAreUniqueAndPersonalToolsAreGated() {
        let context = ToolContext(services: AppServices.preview(), registry: ModuleRegistry(), confirmations: ConfirmationCenter())
        let tools = AssistantToolset.make(context)
        #expect(Set(tools.map(\.name)).count == tools.count)
        #expect(Set(tools.filter(\.requiresRecognizedMember).map(\.name)) == ["get_calendar", "add_reminder", "add_event", "remember_memory", "forget_memory"])
    }

    @Test func memberPreferencesRoundTrip() {
        var prefs = MemberAssistantPreferences(member: HouseholdMember(name: "Kyle"))
        prefs.providerID = "anthropic"
        prefs.model = "claude-sonnet-5-5"
        prefs.personality = .concise
        prefs.aboutMe = String(repeating: "a", count: 400)
        prefs.memories = ["Prefers oat milk latte", "Likes volume at 35%"]
        let member = prefs.applied(to: HouseholdMember(name: "Kyle"))
        #expect(member.preferences["assistantProvider"] == "anthropic")
        let read = MemberAssistantPreferences(member: member)
        #expect(read.personality == .concise)
        #expect(read.aboutMe.count == MemberAssistantPreferences.aboutMeLimit)
        #expect(read.memories == ["Prefers oat milk latte", "Likes volume at 35%"])
    }

    @Test func systemPromptCarriesLiveContext() throws {
        let context = PromptContext(
            now: Date(timeIntervalSince1970: 1_792_594_800), timeZone: try #require(TimeZone(identifier: "America/Chicago")),
            locationName: "Madison", weather: "54°F, Partly Cloudy", memberName: "Kyle", aboutMember: "Vegetarian.",
            memberMemories: ["Loves green tea"], currentVolume: 0.45,
            isPersonalUnlocked: true, personality: .concise,
            homeLines: SystemPromptBuilder.homeLines(for: DemoSmartHomeService().accessories, compact: false),
            toolNames: ["control_device", "get_time"], compact: false
        )
        let prompt = SystemPromptBuilder.build(context)
        #expect(prompt.contains("Wednesday, October 21, 2026 at 10:00 AM"))
        #expect(prompt.contains("Location: Madison."))
        #expect(prompt.contains("Current volume: 45%."))
        #expect(prompt.contains("Speaking with: Kyle, recognized."))
        #expect(prompt.contains("About Kyle, in their words: Vegetarian."))
        #expect(prompt.contains("What you remember about Kyle:\n- Loves green tea"))
        #expect(prompt.contains("Kitchen: Kitchen Lights (light, On, 70%)"))
        #expect(prompt.contains("Tools available: control_device, get_time."))
        #expect(prompt.contains(Personality.concise.instruction))
    }

    @Test func historyKeepsRecentTurnsAsContext() {
        let store = ConversationStore(directory: nil)
        let now = Date()
        store.append(ConversationTurn(date: now.addingTimeInterval(-7200), userText: "old", assistantText: "x", providerName: "Claude"), for: nil)
        store.append(ConversationTurn(date: now, userText: "new", assistantText: "y", providerName: "Claude"), for: nil)
        #expect(store.turns(for: nil).count == 2)
        #expect(store.contextMessages(for: nil, now: now).map(\.text) == ["new", "y"])
        #expect(store.turns(for: UUID()).isEmpty)
    }

    /// Without the tool results, a reply like "I'm playing Evening Star" looked
    /// made up on the next request, and the model apologized for it every time.
    @Test func historyShowsWhatToolsDid() {
        let store = ConversationStore(directory: nil)
        let now = Date()
        store.append(ConversationTurn(date: now, userText: "play some music", assistantText: "Playing Evening Star.",
                                      providerName: "Claude", actions: ["play_music: Now playing Evening Star by Cannons."]), for: nil)
        let reply = store.contextMessages(for: nil, now: now).last?.text ?? ""
        #expect(reply.hasPrefix("[Tools used: play_music: Now playing Evening Star by Cannons.]"))
        #expect(reply.hasSuffix("Playing Evening Star."))
    }

    @Test func cloudSpeechBody() {
        let body = CloudSpeechOutput.body(text: "Hello", voice: .cedar)
        #expect(body["model"] == "gpt-4o-mini-tts")
        #expect(body["voice"] == "cedar")
        #expect(body["input"] == "Hello")
    }

    /// "Done. Now playing: Swan Lake" after a pause made the model say the pause
    /// had failed. Results now say what actually happened.
    @Test func mediaResultsSayWhatHappened() {
        let paused = NowPlaying(title: "Swan Lake", artist: "Tchaikovsky", isPlaying: false, source: .system)
        var playing = paused
        playing.isPlaying = true
        #expect(MediaTools.describe("pause", paused) == "Paused Swan Lake by Tchaikovsky.")
        #expect(MediaTools.describe("pause", playing).hasPrefix("Asked the player to pause, but"))
        #expect(MediaTools.describe("next", playing) == "Playing Swan Lake by Tchaikovsky.")
        #expect(MediaTools.describe("pause", nil) == "Paused.")
    }
}
