import Foundation

/// Event names the Connect module posts or listens for, so other modules can
/// use them without importing HomePadConnect.
///
/// Posted by Connect (others listen):
/// - `kitchen.importRecipeURL`  payload `.string(url)`  a recipe link arrived (share, deep link, Handoff)
/// - `kitchen.importRecipeText` payload `.string(text)` a pasted recipe arrived
/// - `connect.photoReceived`    payload `{"path", "from"}` a shared photo was saved to that file
///
/// Posted by other modules (Connect listens and advertises them over Handoff):
/// - `connect.handoff.recipe`    payload `{"title", "url"}` or `.null` to stop
/// - `connect.handoff.assistant` payload `{"prompt", "answer"}` or `.null` to stop
///
/// The app target posts `openURL` with `.string(url)` for every `homepad://` URL.
public enum ConnectEventName {
    public static let importRecipeURL = "kitchen.importRecipeURL"
    public static let importRecipeText = "kitchen.importRecipeText"
    public static let photoReceived = "connect.photoReceived"
    public static let handoffRecipe = "connect.handoff.recipe"
    public static let handoffAssistant = "connect.handoff.assistant"
    public static let openURL = "openURL"
}

public extension HomePadEvent {
    /// Ask Connect to advertise the recipe on screen for Handoff (nil stops advertising).
    static func handoffRecipe(title: String, url: URL?) -> HomePadEvent {
        var payload: [String: JSONValue] = ["title": .string(title)]
        if let url { payload["url"] = .string(url.absoluteString) }
        return .custom(name: ConnectEventName.handoffRecipe, payload: .object(payload))
    }

    /// Ask Connect to advertise the latest assistant exchange for Handoff.
    static func handoffAssistant(prompt: String, answer: String) -> HomePadEvent {
        .custom(name: ConnectEventName.handoffAssistant, payload: ["prompt": .string(prompt), "answer": .string(answer)])
    }
}
