import CommsKit
import Foundation

extension CommsStore {
    /// Sends file bytes into a conversation through the hub. Throws when not connected,
    /// when the file is over the hub's size cap, or when the hub fails.
    public func sendAttachment(_ data: Data, filename: String, mimeType: String, to conversationID: String) async throws {
        guard let client else { throw HubClient.Failure.unreachable("Not connected to the hub.") }
        try await client.sendAttachment(data, filename: filename, mimeType: mimeType, to: conversationID)
    }

    /// Forwards a received attachment to another conversation. The original is fetched
    /// from the hub (or memory) and sent on, never written to disk here.
    func forward(_ attachment: CommsAttachment, to conversationID: String) async throws {
        guard let attachments else { throw HubClient.Failure.unreachable("Not connected to the hub.") }
        let data = try await attachments.original(attachment.id)
        try await sendAttachment(data, filename: attachment.name, mimeType: attachment.mimeType, to: conversationID)
    }
}
