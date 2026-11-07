import HomePadCore

/// A trace of spoken requests for finding where one goes wrong on a device:
/// the wake phrase, the captured request, the providers that could answer and
/// any error. Launching with `-HomePadAssistantTrace YES` writes
/// Documents/assistant-trace.txt.
@MainActor
enum AssistantTrace {
    static let trace = DebugTrace(file: "assistant-trace.txt", argument: "HomePadAssistantTrace")
}
