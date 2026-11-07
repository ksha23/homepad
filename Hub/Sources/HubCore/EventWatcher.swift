import CommsKit
import Foundation

/// One item on the live stream: a numbered event, or a heartbeat that keeps an idle link alive.
public enum StreamItem: Sendable {
    case event(id: Int, CommsEvent)
    case heartbeat
}

/// Polls chat.db and turns changes into numbered `CommsEvent`s. New messages and read-state
/// changes (made here or synced from the person's other devices through iCloud) both land in
/// the database, so one poll sees both. The last few hundred events are kept, so a client
/// that reconnects can ask for everything after the last number it saw.
public actor EventWatcher {
    private let database: ChatDatabase
    private let interval: Duration
    private let heartbeatEvery: Int
    private let replayLimit = 500

    /// Identifies this run of the hub. Event numbers restart when the hub does, so a client
    /// that sees a new epoch knows its saved position means nothing and reloads.
    public let epoch = Int(Date().timeIntervalSince1970)

    private var lastRowID: Int64
    private var unread: [String: Int]
    private var nextID = 1
    private var recent: [(id: Int, event: CommsEvent)] = []
    private var subscribers: [UUID: AsyncStream<StreamItem>.Continuation] = [:]
    private var task: Task<Void, Never>?
    private var ticks = 0

    public init(database: ChatDatabase, interval: Duration = .seconds(1), heartbeatEvery: Int = 15) throws {
        self.database = database
        self.interval = interval
        self.heartbeatEvery = heartbeatEvery
        lastRowID = try database.latestMessageRowID()
        unread = try database.unreadCounts()
    }

    public func start() {
        guard task == nil else { return }
        task = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: self?.interval ?? .seconds(1))
                await self?.poll()
            }
        }
    }

    public func stop() {
        task?.cancel()
        task = nil
        for continuation in subscribers.values { continuation.finish() }
        subscribers.removeAll()
    }

    /// The newest event number, so a client can tell whether it is up to date.
    public var latestID: Int { nextID - 1 }

    /// Events after `lastID` that are still remembered, then everything live. If the client
    /// is older than the buffer remembers, `gap` is true and it should reload from scratch.
    public func events(after lastID: Int?) -> (stream: AsyncStream<StreamItem>, gap: Bool) {
        let id = UUID()
        let (stream, continuation) = AsyncStream<StreamItem>.makeStream()
        var gap = false
        if let lastID {
            let oldestKept = recent.first?.id ?? nextID
            gap = lastID + 1 < oldestKept
            for entry in recent where entry.id > lastID { continuation.yield(.event(id: entry.id, entry.event)) }
        }
        subscribers[id] = continuation
        continuation.onTermination = { [weak self] _ in
            Task { await self?.removeSubscriber(id) }
        }
        return (stream, gap)
    }

    private func removeSubscriber(_ id: UUID) { subscribers[id] = nil }

    private func publish(_ event: CommsEvent) {
        let id = nextID
        nextID += 1
        recent.append((id, event))
        if recent.count > replayLimit { recent.removeFirst(recent.count - replayLimit) }
        for continuation in subscribers.values { continuation.yield(.event(id: id, event)) }
    }

    func poll() {
        ticks += 1
        if ticks % heartbeatEvery == 0 {
            for continuation in subscribers.values { continuation.yield(.heartbeat) }
        }
        guard let added = try? database.messages(afterRowID: lastRowID) else { return }
        for (rowID, message) in added {
            lastRowID = rowID
            publish(.message(message))
        }
        guard let counts = try? database.unreadCounts() else { return }
        for guid in Set(counts.keys).union(unread.keys) where counts[guid, default: 0] != unread[guid, default: 0] {
            publish(.read(conversationID: guid, unreadCount: counts[guid, default: 0]))
        }
        unread = counts
    }
}
