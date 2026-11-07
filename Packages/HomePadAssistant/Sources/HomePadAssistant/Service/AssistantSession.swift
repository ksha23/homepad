import Foundation
import HomePadCore

/// What the overlay shows for the current exchange.
public struct AssistantSession {
    public var isPresented = false
    /// What the person said or typed.
    public var transcript = ""
    /// The streamed answer so far.
    public var answer = ""
    public var cards: [AssistantCard] = []
    /// A short line while tools run, for example "Checking the weather".
    public var activity: String?
    public var errorMessage: String?
    /// No provider is ready, so the overlay offers setup instead of an answer.
    public var needsSetup = false
    public var providerName: String?
    /// The photo sent with the request, shown as a thumbnail.
    public var attachedImage: Data?
    /// The request came by voice, so follow-ups and spoken answers apply.
    public var isVoice = false

    public init() {}
}

/// Readable activity lines for tool calls.
enum ToolActivity {
    private static let lines: [String: String] = [
        "control_device": "Controlling your home", "list_devices": "Checking your home",
        "activate_scene": "Running the scene", "get_weather": "Checking the weather", "get_time": "Checking the time",
        "get_calendar": "Looking at your calendar", "add_reminder": "Adding a reminder", "add_event": "Adding to your calendar",
        "start_timer": "Starting a timer", "list_timers": "Checking timers", "cancel_timer": "Canceling the timer",
        "play_music": "Finding music", "media_control": "Controlling music", "set_volume": "Changing the volume",
        "intercom_announce": "Announcing", "open_app": "Opening the app", "show_face": "Changing the face",
    ]

    static func describe(_ toolName: String) -> String {
        lines[toolName] ?? "Working on it"
    }
}
