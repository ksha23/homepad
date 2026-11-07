import Foundation
import HubCore

/// `homepad-hub --token-file <path> [--bind <addr>] [--port <n>] [--database <chat.db>]`
/// `--database` points at another Messages database, for testing with a second account.
/// `homepad-hub check` prints counts only, never message text.
var arguments = Array(CommandLine.arguments.dropFirst())

func value(of flag: String) -> String? {
    guard let index = arguments.firstIndex(of: flag), index + 1 < arguments.count else { return nil }
    return arguments[index + 1]
}

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(2)
}

do {
    let database = try ChatDatabase(path: value(of: "--database") ?? ChatDatabase.defaultPath)
    if arguments.first == "check" {
        let conversations = try database.conversations(limit: 20)
        let unread = conversations.map(\.unreadCount).reduce(0, +)
        print("account: \(try database.accountLogin() ?? "unknown"), conversations: \(conversations.count), unread: \(unread)")
        exit(0)
    }
    if arguments.first == "attachment", arguments.count > 1 {
        let found = try database.attachmentFile(guid: arguments[1])
        print(found.map { "\($0.url.path) \($0.mimeType)" } ?? "not found")
        exit(0)
    }
    guard let tokenPath = value(of: "--token-file") else { fail("usage: homepad-hub --token-file <path> [--bind <addr>] [--port <n>]") }
    let token = try String(contentsOfFile: tokenPath, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)
    guard token.count >= 24 else { fail("the token in \(tokenPath) must be at least 24 characters") }

    let server = HubServer(
        database: database,
        watcher: try EventWatcher(database: database),
        actions: MessagesActions(account: try database.accountLogin()),
        config: .init(token: token, bind: value(of: "--bind") ?? "127.0.0.1", port: Int(value(of: "--port") ?? "") ?? 8787)
    )
    try await server.run()
} catch {
    fail("homepad-hub: \(error)")
}
