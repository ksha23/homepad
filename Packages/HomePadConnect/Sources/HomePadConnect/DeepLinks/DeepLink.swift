import Foundation

/// A `homepad://` URL, parsed. Shortcuts, widgets, Handoff, NFC tags and other
/// apps use these to drive a HomePad.
///
///     homepad://app/<id>                  open an app ("timers", "intercom", "board")
///     homepad://face/<id>                 show a face
///     homepad://ask?q=<prompt>            ask the assistant (no q just opens it)
///     homepad://recipe?url=<https url>    import a recipe into Kitchen
///     homepad://timer?minutes=5&label=Tea start a timer (or seconds=)
///     homepad://outbox                    deliver items queued by the Share extension
public enum DeepLink: Equatable, Sendable {
    case app(id: String)
    case face(id: String)
    case ask(prompt: String?)
    case recipe(url: URL)
    case timer(seconds: Double, label: String)
    case outbox

    public static let scheme = "homepad"

    public init?(url: URL) {
        guard url.scheme?.lowercased() == Self.scheme,
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let host = components.host?.lowercased() else { return nil }
        let pathItems = components.path.split(separator: "/").map(String.init)
        let query = Dictionary(
            (components.queryItems ?? []).compactMap { item in item.value.map { (item.name.lowercased(), $0) } },
            uniquingKeysWith: { first, _ in first }
        )
        switch host {
        case "app":
            guard let id = pathItems.first, !id.isEmpty else { return nil }
            self = .app(id: id)
        case "face":
            guard let id = pathItems.first, !id.isEmpty else { return nil }
            self = .face(id: id)
        case "ask":
            let prompt = query["q"]?.trimmingCharacters(in: .whitespacesAndNewlines)
            self = .ask(prompt: prompt?.isEmpty == false ? prompt : nil)
        case "recipe":
            guard let text = query["url"], let recipe = URL(string: text),
                  ["http", "https"].contains(recipe.scheme?.lowercased() ?? "") else { return nil }
            self = .recipe(url: recipe)
        case "timer":
            let seconds = query["seconds"].flatMap(Double.init) ?? query["minutes"].flatMap(Double.init).map { $0 * 60 }
            guard let seconds, seconds > 0, seconds <= 24 * 3600 else { return nil }
            self = .timer(seconds: seconds, label: query["label"] ?? "Timer")
        case "outbox":
            self = .outbox
        default:
            return nil
        }
    }

    /// The canonical URL for this link.
    public var url: URL {
        var components = URLComponents()
        components.scheme = Self.scheme
        switch self {
        case .app(let id):
            components.host = "app"
            components.path = "/\(id)"
        case .face(let id):
            components.host = "face"
            components.path = "/\(id)"
        case .ask(let prompt):
            components.host = "ask"
            if let prompt { components.queryItems = [URLQueryItem(name: "q", value: prompt)] }
        case .recipe(let url):
            components.host = "recipe"
            components.queryItems = [URLQueryItem(name: "url", value: url.absoluteString)]
        case .timer(let seconds, let label):
            components.host = "timer"
            components.queryItems = [URLQueryItem(name: "seconds", value: String(Int(seconds))), URLQueryItem(name: "label", value: label)]
        case .outbox:
            components.host = "outbox"
        }
        return components.url ?? URL(string: "homepad://")!
    }
}
