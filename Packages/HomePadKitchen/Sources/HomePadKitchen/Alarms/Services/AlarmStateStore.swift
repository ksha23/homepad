import Foundation
import HomePadCore

/// What the alarm service keeps across launches.
struct AlarmState: Codable, Equatable {
    var alarms: [HomeAlarm] = []
    /// When each alarm that is on rings next: its next time, or a snooze's end.
    var upcoming: [UUID: Date] = [:]
    /// Alarms whose `upcoming` date is the end of a snooze.
    var snoozed: Set<UUID> = []
}

/// Saves alarms as JSON in Application Support, beside the timers.
struct AlarmStateStore: Sendable {
    let fileURL: URL

    init(fileURL: URL? = nil) {
        self.fileURL = fileURL ?? RecipeLibrary.defaultDirectory.appending(path: "alarms.json")
    }

    func load() -> AlarmState {
        guard let data = try? Data(contentsOf: fileURL) else { return AlarmState() }
        return (try? JSONDecoder().decode(AlarmState.self, from: data)) ?? AlarmState()
    }

    func save(_ state: AlarmState) {
        do {
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(state).write(to: fileURL, options: .atomic)
        } catch {
            Log.make("Kitchen.Alarms").error("Saving alarms failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}
