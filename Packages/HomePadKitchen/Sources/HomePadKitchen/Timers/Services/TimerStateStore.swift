import Foundation
import HomePadCore

/// Saves timers as JSON so they survive relaunches. Running timers store their
/// end date, so time keeps passing while HomePad is closed.
public struct TimerStateStore: Sendable {
    public let fileURL: URL

    public init(fileURL: URL? = nil) {
        self.fileURL = fileURL ?? RecipeLibrary.defaultDirectory.appending(path: "timers.json")
    }

    public func load() -> [HomeTimer] {
        guard let data = try? Data(contentsOf: fileURL) else { return [] }
        return (try? JSONDecoder().decode([HomeTimer].self, from: data)) ?? []
    }

    public func save(_ timers: [HomeTimer]) {
        do {
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(timers).write(to: fileURL, options: .atomic)
        } catch {
            Log.make("Kitchen.Timers").error("Saving timers failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}
