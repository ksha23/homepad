import Foundation

/// What the assistant is doing, for the Siri-style orb overlay.
public enum AssistantPhase: String, Codable, Sendable {
    case idle
    case listening      // capturing speech
    case thinking       // waiting on the model
    case speaking       // reading the answer aloud
    case error
}

/// One request to the assistant. Images let the back-camera "ask about this"
/// feature and others send what the camera sees.
public struct AssistantRequest: Sendable {
    public var text: String
    public var images: [Data]           // JPEG or PNG
    /// Speak the answer aloud when done.
    public var speakResponse: Bool
    /// Show the answer in the assistant overlay.
    public var presentInOverlay: Bool
    /// Optional provider override, for example "anthropic". Nil uses the default.
    public var providerID: String?
    /// A text task another module hands over, such as reading scanned text
    /// into a recipe or events. The provider gets only `text` and `images`:
    /// no tools, no conversation history and nothing about the household or
    /// the person at the screen, and the exchange is kept in nobody's history.
    public var isSelfContained: Bool

    public init(text: String, images: [Data] = [], speakResponse: Bool = true,
                presentInOverlay: Bool = true, providerID: String? = nil, isSelfContained: Bool = false) {
        self.text = text
        self.images = images
        self.speakResponse = speakResponse
        self.presentInOverlay = presentInOverlay
        self.providerID = providerID
        self.isSelfContained = isSelfContained
    }

    /// A self-contained text task (`isSelfContained`): nothing spoken or shown,
    /// and only this text goes to the provider.
    public static func textTask(_ text: String) -> AssistantRequest {
        AssistantRequest(text: text, speakResponse: false, presentInOverlay: false, isSelfContained: true)
    }
}

/// Streamed events while an answer is produced.
public enum AssistantEvent: Sendable {
    case transcript(String)                 // what the user said, as recognized
    case textDelta(String)                  // streamed answer text
    case toolCall(name: String, arguments: String)
    case toolResult(name: String, result: String)
    case card(AssistantCard)                // rich content to show
    case finished(fullText: String)
}

/// Rich content an answer can attach (HomeView shows calendar lists, maps, images).
public struct AssistantCard: Identifiable, Sendable {
    public enum Kind: String, Sendable { case text, calendar, weather, accessory, camera, image, link, timer }
    public var id = UUID()
    public var kind: Kind
    public var title: String
    public var subtitle: String?
    public var url: URL?
    public var payload: JSONValue

    public init(kind: Kind, title: String, subtitle: String? = nil, url: URL? = nil, payload: JSONValue = .null) {
        self.kind = kind
        self.title = title
        self.subtitle = subtitle
        self.url = url
        self.payload = payload
    }
}
