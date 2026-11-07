import Foundation
import Testing
@testable import HomePadConnect

@Suite struct DeepLinkTests {
    private func link(_ text: String) -> DeepLink? {
        URL(string: text).flatMap(DeepLink.init(url:))
    }

    @Test func parsesAppsAndFaces() {
        #expect(link("homepad://app/timers") == .app(id: "timers"))
        #expect(link("HOMEPAD://App/intercom") == .app(id: "intercom"))
        #expect(link("homepad://face/faces.photos") == .face(id: "faces.photos"))
        #expect(link("homepad://app") == nil)
        #expect(link("homepad://face/") == nil)
    }

    @Test func parsesAskWithAndWithoutPrompt() {
        #expect(link("homepad://ask?q=What%27s%20for%20dinner") == .ask(prompt: "What's for dinner"))
        #expect(link("homepad://ask?q=lights+off") == .ask(prompt: "lights+off"))
        #expect(link("homepad://ask") == .ask(prompt: nil))
        #expect(link("homepad://ask?q=%20%20") == .ask(prompt: nil))
    }

    @Test func parsesRecipeOnlyForWebURLs() {
        let recipe = "https://cooking.example.com/recipes/42-french-toast"
        #expect(link("homepad://recipe?url=\(recipe)") == .recipe(url: URL(string: recipe)!))
        #expect(link("homepad://recipe?url=file:///etc/passwd") == nil)
        #expect(link("homepad://recipe") == nil)
    }

    @Test func parsesTimersInMinutesOrSeconds() {
        #expect(link("homepad://timer?minutes=5&label=Tea") == .timer(seconds: 300, label: "Tea"))
        #expect(link("homepad://timer?seconds=90") == .timer(seconds: 90, label: "Timer"))
        #expect(link("homepad://timer?minutes=0") == nil)
        #expect(link("homepad://timer") == nil)
    }

    @Test func rejectsOtherSchemesAndHosts() {
        #expect(link("https://app/timers") == nil)
        #expect(link("homepad://unknown/thing") == nil)
        #expect(link("homepad://outbox") == .outbox)
    }

    @Test func canonicalURLsParseBackToTheSameLink() {
        let links: [DeepLink] = [
            .app(id: "board"), .face(id: "faces.night"), .ask(prompt: "Turn on the lights & fan"), .ask(prompt: nil),
            .recipe(url: URL(string: "https://example.com/r?id=1&x=2")!), .timer(seconds: 600, label: "Pasta water"), .outbox,
        ]
        for original in links {
            #expect(DeepLink(url: original.url) == original)
        }
    }

    @Test func routesLinksToShellEvents() {
        let events = DeepLinkHandler.events(for: .recipe(url: URL(string: "https://example.com/r")!))
        guard case .custom(let name, let payload) = events.first else {
            Issue.record("expected a custom event")
            return
        }
        #expect(name == "kitchen.importRecipeURL")
        #expect(payload == .string("https://example.com/r"))

        guard case .openApp(let id) = DeepLinkHandler.events(for: .app(id: "board")).first else {
            Issue.record("expected openApp")
            return
        }
        #expect(id == "board")

        guard case .invokeAssistant(let prompt) = DeepLinkHandler.events(for: .ask(prompt: "hi")).first else {
            Issue.record("expected invokeAssistant")
            return
        }
        #expect(prompt == "hi")
    }
}
