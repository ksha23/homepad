import AppKit
import CommsKit
import Foundation

/// Things the hub does through the real Messages app. Reading never needs it,
/// so the hub still lists and shows messages if Automation access is missing.
public final class MessagesActions: Sendable {
    public static let version = "0.2.0"

    private let account: String?
    private let outbox: Outbox
    /// How long a sent file stays in the outbox, so Messages can finish copying it.
    private let cleanupDelay: Duration

    public init(account: String?, outbox: Outbox = Outbox(), cleanupDelay: Duration = .seconds(30)) {
        self.account = account
        self.outbox = outbox
        self.cleanupDelay = cleanupDelay
        outbox.purge()
    }

    public func status() async -> HubStatus {
        HubStatus(
            version: Self.version,
            account: account,
            canReadMessages: true,
            canSendMessages: await canRun(#"tell application "Messages" to return (count of services)"#)
        )
    }

    /// Sends `text` to a chat by its GUID.
    public func send(text: String, toConversation guid: String) async throws {
        let script = """
            on run argv
                tell application "Messages" to send (item 1 of argv) to chat id (item 2 of argv)
            end run
            """
        try await AppleScript(source: script).run(arguments: [text, guid])
    }

    /// The script that sends a file. The path and chat arrive as `argv`, never as script text.
    static let sendFileScript = """
        on run argv
            set theFile to POSIX file (item 1 of argv)
            tell application "Messages" to send theFile to chat id (item 2 of argv)
        end run
        """

    /// The arguments for `sendFileScript`.
    static func sendFileArguments(file: URL, conversation guid: String) -> [String] { [file.path, guid] }

    /// Sends uploaded bytes to a chat as a file. The bytes sit in the private outbox
    /// only while the send runs, then the file is deleted.
    public func send(attachment data: Data, filename: String, toConversation guid: String) async throws {
        let file = try outbox.stage(data, filename: filename)
        do {
            try await AppleScript(source: Self.sendFileScript).run(arguments: Self.sendFileArguments(file: file, conversation: guid), timeout: .seconds(60))
        } catch {
            outbox.discard(file)
            throw error
        }
        let outbox = outbox, delay = cleanupDelay
        Task.detached {
            try? await Task.sleep(for: delay)
            outbox.discard(file)
        }
    }

    /// Opens a conversation in Messages by its URL (`ChatAddress.openURL`), which marks it read there
    /// and, through Messages in iCloud, on the person's other devices. Messages only marks a chat read
    /// while it is the active app in an unlocked session, so it comes forward for about a second, then
    /// is hidden again and whatever the person was using gets focus back.
    public func markRead(opening url: URL) async throws {
        try await Task.detached {
            let messagesID = "com.apple.MobileSMS"
            let previous = NSWorkspace.shared.frontmostApplication.flatMap { $0.bundleIdentifier == messagesID ? nil : $0 }
            let open = Process()
            open.executableURL = URL(fileURLWithPath: "/usr/bin/open")
            open.arguments = [url.absoluteString]
            try open.run()
            open.waitUntilExit()
            try await Task.sleep(for: .seconds(1.2))
            NSRunningApplication.runningApplications(withBundleIdentifier: messagesID).first?.hide()
            previous?.activate()
        }.value
    }

    private func canRun(_ source: String) async -> Bool {
        (try? await AppleScript(source: source).run(timeout: .seconds(5))) != nil
    }
}
