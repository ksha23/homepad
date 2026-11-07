import Foundation

/// Event names the Assistant module listens for, so other modules can ask it
/// for things without importing HomePadAssistant.
public enum AssistantEventName {
    /// `.custom` name: say a message in the assistant's voice, as an
    /// announcement. Payload: the text as a string. It is skipped while someone
    /// is talking to the assistant, so it never talks over a request or is heard
    /// as one. Quiet Hours are for the sender to check.
    public static let speak = "assistant.speak"
}

public extension HomePadEvent {
    /// Asks the assistant to say `text` aloud (see `AssistantEventName.speak`).
    static func speak(_ text: String) -> HomePadEvent {
        .custom(name: AssistantEventName.speak, payload: .string(text))
    }
}
