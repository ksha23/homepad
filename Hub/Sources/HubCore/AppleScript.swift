import Foundation

/// Runs AppleScript through `osascript`. Values go in as script arguments
/// (`argv`), never spliced into the source, so message text cannot inject script.
struct AppleScript {
    struct Failure: Error, CustomStringConvertible {
        let output: String
        var description: String { output }
    }

    let source: String

    @discardableResult
    func run(arguments: [String] = [], timeout: Duration = .seconds(20)) async throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", source] + arguments
        let out = Pipe(), err = Pipe()
        process.standardOutput = out
        process.standardError = err
        try process.run()

        let watchdog = Task {
            try await Task.sleep(for: timeout)
            process.terminate()
        }
        // Reading to the end waits for the process to exit.
        let stdout = out.fileHandleForReading.readDataToEndOfFile()
        let stderr = err.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        watchdog.cancel()

        guard process.terminationStatus == 0 else {
            throw Failure(output: String(decoding: stderr, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return String(decoding: stdout, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
