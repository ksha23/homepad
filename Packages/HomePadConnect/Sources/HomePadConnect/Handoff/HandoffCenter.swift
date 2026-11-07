import Foundation
import HomePadCore
import Observation

/// What HomePad offers to Handoff right now, and what to do with activities
/// handed to it. The activity types are declared in the app's Info.plist.
///
/// Kitchen and the assistant announce their content through events
/// (`HomePadEvent.handoffRecipe`, `.handoffAssistant`). Now playing is read
/// from `services.media`.
@MainActor
@Observable
public final class HandoffCenter {
    public enum ActivityType {
        public static let recipe = "com.ksha23.homepad.recipe"
        public static let nowPlaying = "com.ksha23.homepad.nowplaying"
        public static let assistant = "com.ksha23.homepad.assistant"
        public static let camera = "com.ksha23.homepad.camera"
    }

    public struct Recipe: Equatable {
        public var title: String
        public var url: URL?
    }

    public struct Conversation: Equatable {
        public var prompt: String
        public var answer: String
    }

    public private(set) var recipe: Recipe?
    public private(set) var conversation: Conversation?

    @ObservationIgnored private let services: AppServices

    init(services: AppServices) {
        self.services = services
    }

    func start() {
        Task { [weak self, events = services.events] in
            for await event in events.stream() {
                guard case .custom(let name, let payload) = event else { continue }
                self?.handle(name: name, payload: payload)
            }
        }
    }

    // MARK: Advertising

    var advertisesRecipe: Bool { recipe != nil && services.settings[ConnectSettings.handoffRecipes] }
    var advertisesAssistant: Bool { conversation != nil && services.settings[ConnectSettings.handoffAssistant] }
    var nowPlaying: NowPlaying? {
        services.settings[ConnectSettings.handoffNowPlaying] ? services.media.nowPlaying : nil
    }

    func fill(recipe activity: NSUserActivity) {
        guard let recipe else { return }
        activity.title = recipe.title
        activity.webpageURL = recipe.url
        activity.userInfo = ["title": recipe.title, "url": recipe.url?.absoluteString ?? ""]
        activity.isEligibleForHandoff = true
    }

    func fill(nowPlaying activity: NSUserActivity) {
        guard let playing = nowPlaying else { return }
        activity.title = playing.title
        activity.userInfo = ["title": playing.title, "artist": playing.artist ?? "", "album": playing.album ?? ""]
        // Lets a Mac without HomePad pick it up in Apple Music on the web.
        let term = [playing.title, playing.artist].compactMap { $0 }.joined(separator: " ")
        var search = URLComponents(string: "https://music.apple.com/search")
        search?.queryItems = [URLQueryItem(name: "term", value: term)]
        activity.webpageURL = search?.url
        activity.isEligibleForHandoff = true
    }

    func fill(assistant activity: NSUserActivity) {
        guard let conversation else { return }
        activity.title = conversation.prompt
        activity.userInfo = ["prompt": conversation.prompt, "answer": conversation.answer]
        activity.isEligibleForHandoff = true
    }

    // MARK: Receiving

    /// Posts `.handoffReceived` with the activity's user info as JSON.
    func receive(_ activity: NSUserActivity) {
        var payload: [String: JSONValue] = [:]
        for (key, value) in activity.userInfo ?? [:] {
            guard let key = key as? String else { continue }
            switch value {
            case let text as String: payload[key] = .string(text)
            case let number as NSNumber: payload[key] = .number(number.doubleValue)
            default: continue
            }
        }
        if let url = activity.webpageURL { payload["webpageURL"] = .string(url.absoluteString) }
        services.events.post(.handoffReceived(activityType: activity.activityType, payload: .object(payload)))
        services.events.post(.wake)
    }

    private func handle(name: String, payload: JSONValue) {
        switch name {
        case ConnectEventName.handoffRecipe:
            recipe = payload["title"]?.stringValue.map { Recipe(title: $0, url: payload["url"]?.stringValue.flatMap(URL.init(string:))) }
        case ConnectEventName.handoffAssistant:
            if let prompt = payload["prompt"]?.stringValue, let answer = payload["answer"]?.stringValue {
                conversation = Conversation(prompt: prompt, answer: answer)
            } else {
                conversation = nil
            }
        default:
            break
        }
    }
}
