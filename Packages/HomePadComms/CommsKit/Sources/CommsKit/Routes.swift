import Foundation

/// Paths and JSON coding shared by the hub and the module so they cannot drift.
public enum CommsRoutes {
    public static let status = "/v1/status"
    public static let conversations = "/v1/conversations"
    public static let events = "/v1/events"

    public static func messages(in conversationID: String) -> String { "\(conversations)/\(encode(conversationID))/messages" }
    public static func read(_ conversationID: String) -> String { "\(conversations)/\(encode(conversationID))/read" }
    /// Upload a file and send it into a conversation.
    public static func sendAttachment(in conversationID: String) -> String { "\(conversations)/\(encode(conversationID))/attachments" }
    public static func attachment(_ id: String) -> String { "/v1/attachments/\(encode(id))" }

    private static func encode(_ id: String) -> String {
        id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed.subtracting(CharacterSet(charactersIn: "/;"))) ?? id
    }

    public static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    public static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
