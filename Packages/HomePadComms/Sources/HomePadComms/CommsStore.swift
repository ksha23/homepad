import CommsKit
import Foundation
import Observation

/// One member's conversations and threads, in memory only. `lock()` wipes it,
/// so nothing of a person's messages outlives their unlocked session.
@MainActor
@Observable
public final class CommsStore {
    public enum Phase: Equatable {
        case locked
        case notConfigured
        case connecting
        case connected
        case failed(String)
    }

    public private(set) var phase: Phase = .locked
    /// Newest first. Each `unreadCount` is the count HomePad shows: the hub's count with what the
    /// person read on this iPad taken out (`ReadMarkers`). The list's dot, the icon badge and the
    /// Control Center tile all read it here, so they always agree.
    public private(set) var conversations: [CommsConversation] = []
    /// Oldest first, as a thread is drawn.
    public private(set) var threads: [String: [CommsMessage]] = [:]
    /// The newest incoming message, for the banner. Cleared by `dismissBanner()`.
    public private(set) var banner: CommsMessage?
    /// The conversation open on screen, set by the Messages app. Its new messages are
    /// already in view, so they raise no banner.
    public var openConversationID: String?
    public private(set) var account: String?

    /// Loads attachments for the connected member. Nil while locked.
    public private(set) var attachments: AttachmentLoader?

    @ObservationIgnored private(set) var client: HubClient?
    @ObservationIgnored private var listener: Task<Void, Never>?
    @ObservationIgnored private let makeClient: (HubCredentials) -> HubClient
    @ObservationIgnored private let cache: CommsCache?
    @ObservationIgnored private var member: UUID?
    @ObservationIgnored private var lastEventID: Int?
    @ObservationIgnored private var hubEpoch: Int?
    @ObservationIgnored private var saveTask: Task<Void, Never>?
    /// Messages that have already raised a banner, so a replay cannot raise one twice.
    @ObservationIgnored private var notifiedIDs: Set<String> = []
    /// The hub's own unread count per conversation, before HomePad's read markers are applied.
    @ObservationIgnored private var hubUnread: [String: Int] = [:]
    /// What this person has read on this iPad. Saved with their cache, wiped from memory on `lock()`.
    @ObservationIgnored private(set) var readMarkers = ReadMarkers()

    public convenience init(makeClient: @escaping (HubCredentials) -> HubClient = { HubClient(credentials: $0) }) {
        self.init(makeClient: makeClient, cache: nil)
    }

    init(makeClient: @escaping (HubCredentials) -> HubClient = { HubClient(credentials: $0) }, cache: CommsCache?) {
        self.makeClient = makeClient
        self.cache = cache
    }

    public var unreadTotal: Int { conversations.reduce(0) { $0 + $1.unreadCount } }

    /// True while there are messages on screen but the Mac is not answering, so the interface
    /// can show a small "reconnecting" strip instead of replacing the conversations.
    public var isReconnecting: Bool {
        guard !conversations.isEmpty else { return false }
        if case .connected = phase { return false }
        return phase != .locked && phase != .notConfigured
    }

    // MARK: Session

    /// Connects with `credentials`, or shows "not configured" when there are none.
    /// With a `member`, their encrypted cache fills the screen at once while the hub catches up.
    public func connect(_ credentials: HubCredentials?, member: UUID? = nil) {
        lock()
        guard let credentials else { phase = .notConfigured; return }
        self.member = member
        restoreFromCache()
        let client = makeClient(credentials)
        self.client = client
        attachments = AttachmentLoader(client: client)
        phase = .connecting
        listener = Task { [weak self] in await self?.run(client) }
    }

    /// Drops the connection and every message held. The encrypted cache stays on disk.
    public func lock() {
        saveNow()
        saveTask?.cancel()
        saveTask = nil
        listener?.cancel()
        listener = nil
        client = nil
        attachments = nil
        conversations = []
        threads = [:]
        banner = nil
        openConversationID = nil
        notifiedIDs = []
        hubUnread = [:]
        readMarkers = ReadMarkers()
        account = nil
        member = nil
        lastEventID = nil
        hubEpoch = nil
        phase = .locked
    }

    public func dismissBanner() { banner = nil }

    /// Loads the first screen, then follows live events from where this client left off.
    /// Retries until `lock()` cancels it, so a Mac that is asleep or a hub that restarts
    /// reconnects without the person doing anything.
    private func run(_ client: HubClient) async {
        while !Task.isCancelled {
            do {
                let status = try await client.status()
                account = status.account
                show(try await client.conversations())
                phase = .connected
                saveSoon()
                await refreshStaleThreads()
                for try await packet in client.events(after: lastEventID) { handle(packet) }
            } catch {
                if Task.isCancelled { return }
                phase = .failed(error.localizedDescription)
            }
            try? await Task.sleep(for: .seconds(3))
        }
    }

    func handle(_ packet: StreamPacket) {
        switch packet {
        case .hello(let epoch):
            // A different run of the hub: its numbers mean nothing against ours. The
            // conversation list was just reloaded, so start counting from here.
            if hubEpoch != epoch { lastEventID = nil }
            hubEpoch = epoch
        case .gap:
            lastEventID = nil
            Task { [weak self] in
                guard let self, let client = self.client, let fresh = try? await client.conversations() else { return }
                self.show(fresh)
                await self.refreshStaleThreads()
            }
        case .event(let id, let event):
            // An id at or below the last one handled is a replay of something already seen,
            // which updates the lists but must not notify. A new hub run (`hello` with a
            // different epoch) restarted the numbering, so it clears `lastEventID` first.
            let isReplay = id != nil && lastEventID != nil && id! <= lastEventID!
            apply(event, notify: !isReplay)
            if let id { lastEventID = id }
            saveSoon()
        }
    }

    /// Reloads any open or cached thread that has newer messages than we hold, which is
    /// what a reconnect after a long gap leaves behind.
    private func refreshStaleThreads() async {
        for (id, messages) in threads {
            guard let conversation = conversations.first(where: { $0.id == id }),
                  conversation.lastMessageDate > (messages.last?.date ?? .distantPast) else { continue }
            await loadThread(id)
        }
    }

    // MARK: Cache

    private func restoreFromCache() {
        guard let cache, let member, let snapshot = cache.load(member: member) else { return }
        threads = snapshot.threads
        readMarkers = snapshot.readMarkers ?? ReadMarkers()
        // The saved counts already have the markers applied. They stand in for the hub's until it answers.
        show(snapshot.conversations)
        lastEventID = snapshot.lastEventID
        hubEpoch = snapshot.hubEpoch
    }

    /// Saves a couple of seconds after the last change, so a burst of events is one write.
    private func saveSoon() {
        guard cache != nil, member != nil else { return }
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2))
            if !Task.isCancelled { self?.saveNow() }
        }
    }

    private func saveNow() {
        guard let cache, let member, !conversations.isEmpty else { return }
        let snapshot = CacheSnapshot(
            conversations: conversations, threads: threads, lastEventID: lastEventID, hubEpoch: hubEpoch, savedAt: Date(),
            readMarkers: readMarkers
        )
        Task.detached(priority: .utility) { cache.save(snapshot, member: member) }
    }

    /// Moves a person's saved copy to a new member ID: sealed again under a
    /// key made for that ID, and the old file and key removed.
    func moveSavedMessages(from old: UUID, to new: UUID) {
        guard let cache, let snapshot = cache.load(member: old) else { return }
        if cache.save(snapshot, member: new) { cache.delete(member: old) }
    }

    /// Removes this person's saved copy on this iPad: the file and its key.
    public func forgetSavedMessages(for member: UUID) {
        cache?.delete(member: member)
    }

    // MARK: Threads

    public func loadThread(_ id: String) async {
        guard let client, let page = try? await client.messages(in: id, limit: 60) else { return }
        threads[id] = page.reversed()
        refreshUnread(id)
        saveSoon()
    }

    public func send(_ text: String, to id: String) async -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let client, !trimmed.isEmpty else { return false }
        do {
            try await client.send(trimmed, to: id)
            return true
        } catch {
            phase = .failed(error.localizedDescription)
            return false
        }
    }

    // MARK: Read state

    /// The person has this conversation in front of them. HomePad counts it read through its newest
    /// message at once and keeps it that way, whatever the Mac does (`ReadMarkers`).
    func markSeen(_ id: String) {
        guard let newest = newestDate(in: id) else { return }
        readMarkers.markSeen(id, through: newest)
        refreshUnread(id)
        if banner?.conversationID == id { banner = nil }
        saveSoon()
    }

    /// Marks the conversation read on this iPad (`markSeen`), then asks the Mac to mark it read in
    /// Messages, which reaches the person's other devices through iCloud. The Mac can do that only
    /// while its screen is unlocked, and HomePad's dot does not wait for it.
    public func markRead(_ id: String) async {
        markSeen(id)
        try? await client?.markRead(id)
    }

    /// Shows a list of conversations from the hub (or the cache). The hub's counts are kept aside,
    /// and each conversation shows HomePad's count.
    private func show(_ list: [CommsConversation]) {
        hubUnread = Dictionary(list.map { ($0.id, $0.unreadCount) }, uniquingKeysWith: { first, _ in first })
        conversations = list
        for index in conversations.indices { refreshUnread(at: index) }
    }

    private func refreshUnread(_ id: String) {
        guard let index = conversations.firstIndex(where: { $0.id == id }) else { return }
        refreshUnread(at: index)
    }

    /// Sets one conversation's count from the hub's count and the person's marker.
    /// The conversation on screen is seen through its newest message first.
    private func refreshUnread(at index: Int) {
        let id = conversations[index].id
        let newest = newestDate(of: conversations[index])
        if id == openConversationID { readMarkers.markSeen(id, through: newest) }
        let count = readMarkers.unreadCount(id, hubCount: hubUnread[id, default: 0], newest: newest, thread: threads[id])
        if conversations[index].unreadCount != count { conversations[index].unreadCount = count }
    }

    /// The date of the newest message HomePad knows of in a conversation, from the list or its thread.
    private func newestDate(of conversation: CommsConversation) -> Date {
        max(conversation.lastMessageDate, threads[conversation.id]?.last?.date ?? .distantPast)
    }

    private func newestDate(in id: String) -> Date? {
        if let conversation = conversations.first(where: { $0.id == id }) { return newestDate(of: conversation) }
        return threads[id]?.last?.date
    }

    // MARK: Events

    /// A message older than this is history arriving late, not news.
    static let freshWindow: TimeInterval = 120

    func apply(_ event: CommsEvent, notify: Bool = true) {
        switch event {
        case .message(let message):
            if var thread = threads[message.conversationID], !thread.contains(where: { $0.id == message.id }) {
                thread.append(message)
                threads[message.conversationID] = thread
            }
            // Sending a message counts as reading everything before it, as in Messages.
            if message.isFromMe { readMarkers.markSeen(message.conversationID, through: message.date) }
            applyToList(message)
            if notify && shouldNotify(message) { banner = message }
            // A message that arrives in the conversation on screen is read here, so the Mac is asked to mark it too.
            if notify, message.conversationID == openConversationID, !message.isFromMe, !message.isRead, let client {
                Task { try? await client.markRead(message.conversationID) }
            }
        case .read(let id, let unread):
            hubUnread[id] = unread
            refreshUnread(id)
            let shown = conversations.first(where: { $0.id == id })?.unreadCount ?? unread
            if banner?.conversationID == id && shown == 0 { banner = nil }
        }
    }

    /// True once per new incoming message that the person has not seen: not their own,
    /// not already read, not in the conversation on screen, and not old.
    private func shouldNotify(_ message: CommsMessage) -> Bool {
        guard !message.isFromMe, !message.isRead,
              message.conversationID != openConversationID,
              abs(message.date.timeIntervalSinceNow) < Self.freshWindow else { return false }
        return notifiedIDs.insert(message.id).inserted
    }

    private func applyToList(_ message: CommsMessage) {
        let id = message.conversationID
        if !message.isFromMe && !message.isRead { hubUnread[id, default: 0] += 1 }
        guard let index = conversations.firstIndex(where: { $0.id == id }) else {
            Task { [weak self] in
                guard let self, let client = self.client, let fresh = try? await client.conversations() else { return }
                self.show(fresh)
            }
            return
        }
        var conversation = conversations.remove(at: index)
        conversation.lastMessagePreview = message.text
        conversation.lastMessageDate = message.date
        conversations.insert(conversation, at: 0)
        refreshUnread(at: 0)
    }
}
