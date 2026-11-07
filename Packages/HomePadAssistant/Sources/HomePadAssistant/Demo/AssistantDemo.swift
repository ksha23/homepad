import Foundation
import HomePadCore

/// Launch arguments that put the assistant into a fixed state for simulator
/// screenshots. Nothing here calls a provider.
///
///     -HomePadAssistantDemo listening|thinking|answer|calendar|home|weather|confirm|setup|error|chat
///     -HomePadAssistantTab chat|settings      (with -HomePadOpenApp assistant)
///     -HomePadAssistantProvider <providerID>  (also opens that provider's settings sheet)
@MainActor
enum AssistantDemo {
    static var requestedState: String? { UserDefaults.standard.string(forKey: "HomePadAssistantDemo") }
    static var requestedTab: AssistantAppTab? {
        UserDefaults.standard.string(forKey: "HomePadAssistantTab").flatMap(AssistantAppTab.init(rawValue:))
    }

    static var requestedProvider: ProviderDescriptor? {
        UserDefaults.standard.string(forKey: "HomePadAssistantProvider").flatMap(ProviderCatalog.descriptor)
    }

    static func apply(to runtime: AssistantRuntime) {
        guard let state = requestedState else { return }
        var session = AssistantSession()
        session.isPresented = true
        session.isVoice = true
        session.providerName = "Claude"
        switch state {
        case "listening":
            session.transcript = "What's on my calendar this afternoon"
            runtime.phase = .listening
        case "thinking":
            session.transcript = "Turn off the downstairs lights and set the thermostat to 68"
            session.activity = "Controlling your home"
            runtime.phase = .thinking
        case "answer":
            session.transcript = "Is French toast originally from France?"
            session.answer = "**No**, French toast is not originally from France. Its earliest known origins trace back to **ancient Rome**, where bread was soaked in milk and fried. In France it is called **pain perdu**, which means lost bread."
            session.cards = [
                CardFactory.link(URL(string: "https://en.wikipedia.org/wiki/French_toast")!, title: "French toast"),
                CardFactory.link(URL(string: "https://www.britannica.com/topic/French-toast")!, title: "French toast, Britannica"),
                CardFactory.link(URL(string: "https://www.smithsonianmag.com/arts-culture/french-toast")!, title: "A short history of French toast"),
                CardFactory.link(URL(string: "https://www.seriouseats.com/french-toast")!, title: "The best French toast"),
            ]
            runtime.phase = .speaking
        case "calendar":
            session.transcript = "What birthdays are coming up?"
            session.answer = "Here are the upcoming birthday celebrations on your calendar:"
            session.cards = [CardFactory.calendar(sampleEvents(), title: "Birthdays")]
        case "home":
            session.transcript = "Turn off the lights and set the thermostat to 68"
            session.answer = "Done. The kitchen and entryway lights are off and the thermostat is set to 68 degrees."
            session.cards = [CardFactory.accessories(changedAccessories(runtime.services.smartHome.accessories), title: "Home")]
        case "weather":
            session.transcript = "Do I need a jacket today?"
            session.answer = "Yes, bring a light jacket. It's 54 degrees and partly cloudy, with a high of 57."
            if let weather = runtime.services.weather.current { session.cards = [CardFactory.weather(weather)] }
        case "confirm":
            // Not a voice session, so the demo never opens the microphone.
            session.isVoice = false
            session.transcript = "Unlock the front door"
            runtime.session = session
            runtime.phase = .thinking
            Task { _ = await runtime.confirmations.confirm("Unlock the Front Door?") }
            return
        case "setup":
            session.providerName = nil
            session.needsSetup = true
        case "error":
            session.transcript = "What's the weather in Tokyo?"
            session.errorMessage = AssistantError.http(status: 401, message: "").errorDescription
            runtime.phase = .error
        case "chat":
            seedChat(runtime)
            return
        default:
            return
        }
        runtime.session = session
    }

    /// The lights and thermostat as they would look after the "home" demo request.
    private static func changedAccessories(_ accessories: [HomeAccessory]) -> [HomeAccessory] {
        accessories.filter { $0.kind == .light || $0.kind == .thermostat }.map { accessory in
            var changed = accessory
            if accessory.kind == .light { changed.state.isOn = false }
            if accessory.kind == .thermostat { changed.state.targetTemperature = 68 }
            return changed
        }
    }

    private static func sampleEvents() -> [CalendarItem] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let day = { (offset: Int) in calendar.date(byAdding: .day, value: offset, to: today) ?? today }
        return [
            CalendarItem(id: "1", title: "Sam's birthday", start: day(2), end: day(3), isAllDay: true, colorHex: "#FF9500"),
            CalendarItem(id: "2", title: "Birthday party for Jordan and the neighbors", start: day(9).addingTimeInterval(15 * 3600),
                         end: day(9).addingTimeInterval(16 * 3600), colorHex: "#0A84FF"),
            CalendarItem(id: "3", title: "Grandma's birthday", start: day(20), end: day(21), isAllDay: true, colorHex: "#FF9500"),
        ]
    }

    /// Adds a short sample conversation for guests, once.
    private static func seedChat(_ runtime: AssistantRuntime) {
        guard runtime.conversations.turns(for: nil).isEmpty else { return }
        let samples = [
            ("What's a good pasta for a weeknight?", "Try **spaghetti aglio e olio**. It takes **15 minutes**: garlic, olive oil, chili flakes and parsley."),
            ("Set a timer for the pasta", "Started a 10 minute pasta timer."),
            ("Turn the kitchen lights down a bit", "Done. The kitchen lights are at **45%**."),
        ]
        for (question, answer) in samples {
            runtime.conversations.append(ConversationTurn(userText: question, assistantText: answer, providerName: "Apple Intelligence"), for: nil)
        }
    }
}
