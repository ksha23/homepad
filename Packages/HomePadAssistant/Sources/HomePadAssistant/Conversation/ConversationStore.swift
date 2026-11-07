import Foundation
import HomePadCore
import Observation

/// One exchange, as kept in history.
public struct ConversationTurn: Codable, Identifiable, Hashable, Sendable {
    public var id: UUID
    public var date: Date
    public var userText: String
    public var assistantText: String
    public var providerName: String
    public var hadImage: Bool
    /// What the tools did during the turn. Optional so older saved turns still load.
    public var actions: [String]?

    public init(id: UUID = UUID(), date: Date = Date(), userText: String, assistantText: String, providerName: String,
                hadImage: Bool = false, actions: [String]? = nil) {
        self.id = id
        self.date = date
        self.userText = userText
        self.assistantText = assistantText
        self.providerName = providerName
        self.hadImage = hadImage
        self.actions = actions
    }

    /// The reply as context for the next request. Saved text alone showed
    /// "I'm playing Evening Star" with no tool call behind it, so the model
    /// decided it had made that up and apologized at length in every answer.
    var contextReply: String {
        guard let actions, !actions.isEmpty else { return assistantText }
        return "[Tools used: \(actions.joined(separator: "; "))]\n\(assistantText)"
    }
}

/// Per-person conversation history, saved on this iPad only (Application
/// Support), with guests kept separately. Recent turns become model context
/// so follow-ups like "and tomorrow?" work.
@MainActor
@Observable
public final class ConversationStore {
    /// Turns kept per person on disk.
    static let storedTurns = 50
    /// Turns sent to the model as context.
    static let contextTurns = 8
    /// Older turns are shown in the app but not sent as context.
    static let contextWindow: TimeInterval = 60 * 60

    /// Bumped on every change, so views that read history refresh.
    public private(set) var revision = 0
    @ObservationIgnored private var cache: [String: [ConversationTurn]] = [:]
    @ObservationIgnored private let directory: URL?
    private let log = Log.make("AssistantHistory")

    /// Pass nil to keep history in memory only (previews and tests).
    public init(directory: URL? = ConversationStore.defaultDirectory) {
        self.directory = directory
    }

    nonisolated public static var defaultDirectory: URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appending(path: "HomePadAssistant", directoryHint: .isDirectory)
    }

    public func turns(for memberID: UUID?) -> [ConversationTurn] {
        _ = revision
        let key = Self.key(memberID)
        if let cached = cache[key] { return cached }
        let loaded = load(key)
        cache[key] = loaded
        return loaded
    }

    /// Recent turns as alternating user and assistant messages.
    func contextMessages(for memberID: UUID?, now: Date = Date()) -> [ChatMessage] {
        turns(for: memberID)
            .filter { now.timeIntervalSince($0.date) < Self.contextWindow }
            .suffix(Self.contextTurns)
            .flatMap { [ChatMessage.user($0.userText), ChatMessage.assistant($0.contextReply)] }
    }

    func append(_ turn: ConversationTurn, for memberID: UUID?) {
        let key = Self.key(memberID)
        var list = turns(for: memberID)
        list.append(turn)
        list = Array(list.suffix(Self.storedTurns))
        cache[key] = list
        save(list, key: key)
        revision += 1
    }

    /// Keeps a person's history theirs under the ID the household knows them
    /// by, after this HomePad joined a household that already had them.
    func moveMember(from old: UUID, to new: UUID) {
        let list = turns(for: old)
        guard !list.isEmpty else { return }
        let key = Self.key(new)
        cache[key] = list
        save(list, key: key)
        clear(for: old)
    }

    public func clear(for memberID: UUID?) {
        let key = Self.key(memberID)
        cache[key] = []
        save([], key: key)
        revision += 1
    }

    private static func key(_ memberID: UUID?) -> String {
        memberID?.uuidString ?? "guest"
    }

    private func fileURL(_ key: String) -> URL? {
        directory?.appending(path: "history-\(key).json")
    }

    private func load(_ key: String) -> [ConversationTurn] {
        guard let url = fileURL(key), let data = try? Data(contentsOf: url) else { return [] }
        return (try? JSONDecoder().decode([ConversationTurn].self, from: data)) ?? []
    }

    private func save(_ turns: [ConversationTurn], key: String) {
        guard let directory, let url = fileURL(key) else { return }
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try JSONEncoder().encode(turns).write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        } catch {
            log.error("Could not save history: \(error.localizedDescription, privacy: .public)")
        }
    }
}
