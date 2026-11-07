import Foundation

/// A timestamped text log in the app's Documents folder, for following what a
/// feature does on a device. Off unless the app was launched with its argument
/// (`-<argument> YES`), or Documents holds a file named `<argument>.on` written in
/// the last day. A launch argument is gone once the app is restarted on the iPad,
/// and the file is not, so copy it there to follow something across restarts. It
/// stops counting after a day, since devicectl cannot delete it again:
/// `xcrun devicectl device copy to --domain-type appDataContainer --source <empty file> --destination Documents/<argument>.on`.
/// Fetch the log with
/// `xcrun devicectl device copy from --domain-type appDataContainer --source Documents/<file>`.
///
/// A file never grows past `maximumBytes` (64 MB). Past it, the oldest half is
/// dropped and the newest 32 MB, whole lines, are kept. A trace left on for a
/// day once reached 400 MB, and the device copy stops at about 410 MB.
///
///     static let trace = DebugTrace(file: "presence-trace.txt", argument: "HomePadPresenceTrace")
///     trace.log("recognized \(name)")
@MainActor
public final class DebugTrace {
    public let isEnabled: Bool
    /// Largest a trace file may grow, in bytes.
    public static let maximumBytes = 64 * 1024 * 1024
    /// One queue writes every trace file, off the main actor, in order.
    private static let writer = DispatchQueue(label: "com.homepad.debugtrace", qos: .utility)
    private let file: String
    /// Every trace counts from the same moment, so their lines can be merged.
    private let start = DebugTrace.sharedStart
    private static let sharedStart = Date()
    private var lines: [String] = []
    private var flushTask: Task<Void, Never>?
    private var lastByKey: [String: String] = [:]

    public init(file: String, argument: String) {
        self.file = file
        // `-<argument> YES`, or any other word than an off value, such as a mode
        // (`-HomePadAudioTrace verbose`), which bool(forKey:) reads as false.
        let value = UserDefaults.standard.string(forKey: argument)?.lowercased()
        isEnabled = UserDefaults.standard.bool(forKey: argument)
            || (value.map { !$0.isEmpty && !["no", "false", "0"].contains($0) } ?? false)
            || Self.hasSwitchFile(for: argument)
    }

    /// True when Documents holds `<argument>.on`, written in the last day.
    private static func hasSwitchFile(for argument: String) -> Bool {
        guard let folder = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first,
              let attributes = try? FileManager.default.attributesOfItem(atPath: folder.appendingPathComponent("\(argument).on").path),
              let written = attributes[.modificationDate] as? Date else { return false }
        return Date().timeIntervalSince(written) < 24 * 60 * 60
    }

    /// Appends a line, timed from launch.
    public func log(_ text: @autoclosure () -> String) {
        guard isEnabled else { return }
        lines.append(String(format: "%8.3f ", Date().timeIntervalSince(start)) + text())
        guard flushTask == nil else { return }
        flushTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1))
            self?.flush()
        }
    }

    /// Appends a line only when it differs from the last one logged under `key`,
    /// for state that is reported many times a second.
    public func logIfChanged(_ key: String, _ text: @autoclosure () -> String) {
        guard isEnabled else { return }
        let line = text()
        guard lastByKey[key] != line else { return }
        lastByKey[key] = line
        log(line)
    }

    private func flush() {
        flushTask = nil
        guard !lines.isEmpty, let folder = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { return }
        let url = folder.appendingPathComponent(file)
        let text = lines.joined(separator: "\n") + "\n"
        lines.removeAll()
        let maximumBytes = Self.maximumBytes
        Self.writer.async {
            DebugTrace.append(text, to: url, maximumBytes: maximumBytes)
        }
    }

    /// Appends `text` to the file, then drops its oldest half when it grew
    /// past `maximumBytes`.
    nonisolated static func append(_ text: String, to url: URL, maximumBytes: Int) {
        let size: UInt64
        if let handle = try? FileHandle(forWritingTo: url) {
            handle.seekToEndOfFile()
            handle.write(Data(text.utf8))
            size = handle.offsetInFile
            try? handle.close()
        } else {
            try? text.write(to: url, atomically: true, encoding: .utf8)
            size = UInt64(text.utf8.count)
        }
        if size > UInt64(maximumBytes) {
            try? keepNewest(of: url, bytes: maximumBytes / 2)
        }
    }

    /// Keeps the last `bytes` of the file, starting at its first whole line,
    /// under a line that says older ones were dropped.
    nonisolated static func keepNewest(of url: URL, bytes: Int) throws {
        let handle = try FileHandle(forReadingFrom: url)
        let size = try handle.seekToEnd()
        guard size > UInt64(bytes) else {
            try handle.close()
            return
        }
        try handle.seek(toOffset: size - UInt64(bytes))
        let tail = try handle.readToEnd() ?? Data()
        try handle.close()
        var kept = tail
        if let newline = tail.firstIndex(of: 0x0A) {
            kept = Data(tail[tail.index(after: newline)...])
        }
        let note = "(older lines were dropped: this trace keeps its newest \(bytes / (1024 * 1024)) MB)\n"
        try (Data(note.utf8) + kept).write(to: url, options: .atomic)
    }
}
