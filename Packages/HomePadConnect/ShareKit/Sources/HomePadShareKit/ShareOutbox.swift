import Foundation

/// A small file queue in the App Group container. The "Send to HomePad" Share
/// extension writes items here, and the app sends them over the peer link.
///
/// Layout inside `group.com.ksha23.homepad`:
///
///     Outbox/<id>.json       a SharedItem
///     Outbox/<id>.jpg        its photo, if any
///     Outbox/targets.json    HomePads the app knows about, for the extension's picker
public struct ShareOutbox: Sendable {
    public static let appGroup = "group.com.ksha23.homepad"
    /// Darwin notification the extension posts after enqueueing, so a running app delivers at once.
    public static let didEnqueueNotification = "com.ksha23.homepad.outbox.didEnqueue"

    /// A HomePad the extension can offer as a target.
    public struct Target: Codable, Hashable, Identifiable, Sendable {
        public var id: String
        public var name: String
        public init(id: String, name: String) {
            self.id = id
            self.name = name
        }
    }

    /// One queued item and its optional image file.
    public struct Entry: Sendable {
        public var item: SharedItem
        public var imageURL: URL?
    }

    public let directory: URL

    public init(directory: URL) {
        self.directory = directory
    }

    /// The shared outbox, or nil when the App Group is not available (unsigned builds, tests).
    public static func shared() -> ShareOutbox? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup)
            .map { ShareOutbox(directory: $0.appendingPathComponent("Outbox", isDirectory: true)) }
    }

    public func enqueue(_ item: SharedItem, image: Data?) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        if let image {
            try image.write(to: imageURL(for: item.id), options: .atomic)
        }
        try Self.encoder.encode(item).write(to: itemURL(for: item.id), options: .atomic)
    }

    /// Queued items, oldest first.
    public func pending() -> [Entry] {
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        return files
            .filter { $0.pathExtension == "json" && $0.lastPathComponent != "targets.json" }
            .compactMap { url -> Entry? in
                guard let data = try? Data(contentsOf: url),
                      let item = try? Self.decoder.decode(SharedItem.self, from: data) else { return nil }
                let image = imageURL(for: item.id)
                return Entry(item: item, imageURL: FileManager.default.fileExists(atPath: image.path) ? image : nil)
            }
            .sorted { $0.item.sentAt < $1.item.sentAt }
    }

    public func remove(_ id: UUID) {
        try? FileManager.default.removeItem(at: itemURL(for: id))
        try? FileManager.default.removeItem(at: imageURL(for: id))
    }

    public func saveTargets(_ targets: [Target]) {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try? JSONEncoder().encode(targets).write(to: directory.appendingPathComponent("targets.json"), options: .atomic)
    }

    public func targets() -> [Target] {
        guard let data = try? Data(contentsOf: directory.appendingPathComponent("targets.json")) else { return [] }
        return (try? JSONDecoder().decode([Target].self, from: data)) ?? []
    }

    /// Wakes a running app so it delivers right away.
    public static func notifyApp() {
        CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),
                                             CFNotificationName(didEnqueueNotification as CFString), nil, nil, true)
    }

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    private func itemURL(for id: UUID) -> URL { directory.appendingPathComponent("\(id.uuidString).json") }
    private func imageURL(for id: UUID) -> URL { directory.appendingPathComponent("\(id.uuidString).jpg") }
}
