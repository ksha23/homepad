import CommsKit
import Foundation
import Hummingbird
import NIOCore
import UniformTypeIdentifiers

/// The hub's HTTP API (see docs/COMMS.md).
public struct HubServer {
    public struct Config {
        public var token: String
        public var bind: String
        public var port: Int
        public init(token: String, bind: String = "127.0.0.1", port: Int = 8787) {
            self.token = token
            self.bind = bind
            self.port = port
        }
    }

    let database: ChatDatabase
    let watcher: EventWatcher
    let actions: MessagesActions
    let config: Config

    public init(database: ChatDatabase, watcher: EventWatcher, actions: MessagesActions, config: Config) {
        self.database = database
        self.watcher = watcher
        self.actions = actions
        self.config = config
    }

    public func run() async throws {
        await watcher.start()
        let app = Application(
            router: makeRouter(),
            configuration: .init(address: .hostname(config.bind, port: config.port))
        )
        try await app.runService()
    }

    func makeRouter() -> Router<BasicRequestContext> {
        let router = Router()
        router.add(middleware: TokenAuth(token: config.token))
        router.get(RouterPath(String(CommsRoutes.status.dropFirst()))) { _, _ in
            try Self.json(await actions.status())
        }
        router.get(RouterPath(String(CommsRoutes.conversations.dropFirst()))) { request, _ in
            let limit = request.uri.queryParameters.get("limit", as: Int.self) ?? 50
            return try Self.json(try database.conversations(limit: min(max(limit, 1), 200)))
        }
        router.get("v1/conversations/:id/messages") { request, context in
            let id = try Self.conversationID(context)
            let limit = request.uri.queryParameters.get("limit", as: Int.self) ?? 50
            let before = request.uri.queryParameters.get("before").flatMap { ISO8601DateFormatter().date(from: $0) }
            return try Self.json(try database.messages(inConversation: id, before: before, limit: min(max(limit, 1), 200)))
        }
        router.post("v1/conversations/:id/messages") { request, context in
            let id = try Self.conversationID(context)
            let body = try await request.decode(as: SendMessageRequest.self, context: context)
            try await actions.send(text: body.text, toConversation: id)
            return Response(status: .accepted)
        }
        router.post("v1/conversations/:id/attachments") { request, context in
            let id = try Self.conversationID(context)
            if let length = request.headers[.contentLength].flatMap({ Int($0) }), !CommsUpload.allows(length) {
                throw HTTPError(.contentTooLarge)
            }
            let buffer = try await request.body.collect(upTo: CommsUpload.maxBytes)
            guard buffer.readableBytes > 0 else { throw HTTPError(.badRequest) }
            let name = Self.uploadName(
                header: request.headers.first { $0.name.rawName.lowercased() == CommsUpload.filenameHeader.lowercased() }?.value,
                contentType: request.headers[.contentType]
            )
            try await actions.send(attachment: Data(buffer: buffer), filename: name, toConversation: id)
            return Response(status: .accepted)
        }
        router.post("v1/conversations/:id/read") { _, context in
            let id = try Self.conversationID(context)
            guard (try database.unreadCounts()[id] ?? 0) > 0 else { return Response(status: .accepted) }
            // No URL is sure to open a group without a group ID, and opening another chat would mark that one
            // read instead. The iPad keeps its own read state either way.
            guard let url = try database.address(ofChat: id)?.openURL else { return Response(status: .accepted) }
            // Messages writes the change some time after the chat opens, several seconds for a text that goes
            // through the iPhone (SMS, RCS). The event stream reports it (`EventWatcher`), so the reply does not wait.
            try await actions.markRead(opening: url)
            return Response(status: .accepted)
        }
        router.get("v1/attachments/:id") { request, context in
            let id = try Self.conversationID(context)
            guard let file = try database.attachmentFile(guid: id) else { throw HTTPError(.notFound) }
            let wantsThumbnail = request.uri.queryParameters.get("size") == "thumb"
            if wantsThumbnail, file.mimeType.hasPrefix("image/") || file.mimeType == "application/pdf", file.mimeType != "image/gif",
               let thumbnail = Thumbnails.jpeg(for: file.url, guid: id) {
                return try AttachmentResponse.make(file: thumbnail, mimeType: "image/jpeg", rangeHeader: nil)
            }
            return try AttachmentResponse.make(file: file.url, mimeType: file.mimeType, rangeHeader: request.headers[.range])
        }
        router.get("v1/contacts/photo") { request, _ in
            guard let handle = request.uri.queryParameters.get("handle"), let data = database.contactPhoto(for: handle) else { throw HTTPError(.notFound) }
            var headers = HTTPFields()
            headers[.contentType] = "image/jpeg"
            headers[.cacheControl] = "private, max-age=3600"
            return Response(status: .ok, headers: headers, body: .init(byteBuffer: ByteBuffer(data: data)))
        }
        router.get(RouterPath(String(CommsRoutes.events.dropFirst()))) { request, _ in
            let last = request.headers.first { $0.name.rawName.lowercased() == "last-event-id" }.flatMap { Int($0.value) }
            return await events(lastEventID: last)
        }
        return router
    }

    /// Server-sent events. Each carries a number, so a client that reconnects can send
    /// `Last-Event-ID` and get what it missed. A `gap` event tells it the buffer no longer
    /// reaches back that far and it should reload.
    private func events(lastEventID: Int?) async -> Response {
        let (stream, gap) = await watcher.events(after: lastEventID)
        let epoch = watcher.epoch
        var headers = HTTPFields()
        headers[.contentType] = "text/event-stream"
        headers[.cacheControl] = "no-cache"
        return Response(status: .ok, headers: headers, body: .init { writer in
            let encoder = CommsRoutes.makeEncoder()
            try await writer.write(ByteBuffer(string: "event: hello\ndata: {\"epoch\":\(epoch)}\n\n"))
            if gap { try await writer.write(ByteBuffer(string: "event: gap\ndata: {}\n\n")) }
            for await item in stream {
                switch item {
                case .heartbeat:
                    try await writer.write(ByteBuffer(string: ": ping\n\n"))
                case .event(let id, let event):
                    guard let data = try? encoder.encode(event) else { continue }
                    try await writer.write(ByteBuffer(string: "id: \(id)\ndata: " + String(decoding: data, as: UTF8.self) + "\n\n"))
                }
            }
            try await writer.finish(nil)
        })
    }

    /// Chat GUIDs contain `;` and `+`, so the iPad sends them percent-encoded.
    static func conversationID(_ context: BasicRequestContext) throws -> String {
        let raw = try context.parameters.require("id")
        return raw.removingPercentEncoding ?? raw
    }

    /// A safe file name for an upload. The `X-Filename` header is percent-decoded, and a
    /// name with no extension gets one from the content type.
    static func uploadName(header: String?, contentType: String?) -> String {
        var name = CommsUpload.sanitizedFilename(header.map { $0.removingPercentEncoding ?? $0 })
        if (name as NSString).pathExtension.isEmpty,
           let mime = contentType?.split(separator: ";").first.map(String.init),
           let ext = UTType(mimeType: mime.trimmingCharacters(in: .whitespaces))?.preferredFilenameExtension {
            name += "." + ext
        }
        return name
    }

    static func json<T: Encodable>(_ value: T) throws -> Response {
        let data = try CommsRoutes.makeEncoder().encode(value)
        return Response(status: .ok, headers: [.contentType: "application/json"], body: .init(byteBuffer: ByteBuffer(data: data)))
    }
}
