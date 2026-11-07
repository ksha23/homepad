import Foundation
import Testing
@testable import HomePadCameraLab

@Suite struct SecurityScheduleTests {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Chicago")!
        return calendar
    }()

    private func date(hour: Int, minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: 20, hour: hour, minute: minute))!
    }

    @Test func alwaysWatches() {
        #expect(SecuritySchedule.always.shouldWatch(now: date(hour: 12), calendar: calendar, lastSeenSomeone: date(hour: 12)))
    }

    @Test func nightWindowWrapsPastMidnight() {
        let night = SecuritySchedule.atNight
        #expect(night.shouldWatch(now: date(hour: 23, minute: 5), calendar: calendar, lastSeenSomeone: nil))
        #expect(night.shouldWatch(now: date(hour: 3), calendar: calendar, lastSeenSomeone: nil))
        #expect(!night.shouldWatch(now: date(hour: 7), calendar: calendar, lastSeenSomeone: nil))
        #expect(!night.shouldWatch(now: date(hour: 15), calendar: calendar, lastSeenSomeone: nil))
    }

    @Test func awayStartsAfterTwentyQuietMinutes() {
        let away = SecuritySchedule.whenAway
        let now = date(hour: 14)
        #expect(!away.shouldWatch(now: now, calendar: calendar, lastSeenSomeone: now.addingTimeInterval(-19 * 60)))
        #expect(away.shouldWatch(now: now, calendar: calendar, lastSeenSomeone: now.addingTimeInterval(-21 * 60)))
    }
}

@MainActor
@Suite struct SnapshotRingBufferTests {
    private func directory() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("cameralab-snapshots-\(UUID().uuidString)", isDirectory: true)
    }

    @Test func keepsTheNewestUpToTheLimit() throws {
        let folder = directory()
        let buffer = SnapshotRingBuffer(directory: folder, limit: 3)
        var added: [MotionSnapshot] = []
        for index in 0..<5 {
            added.append(try buffer.add(jpeg: Data([0xFF, 0xD8, UInt8(index)]), personDetected: index.isMultiple(of: 2)))
        }
        #expect(buffer.snapshots.map(\.id) == added.suffix(3).reversed().map(\.id))
        #expect(!FileManager.default.fileExists(atPath: buffer.url(for: added[0]).path))
        #expect(FileManager.default.fileExists(atPath: buffer.url(for: added[4]).path))

        let reopened = SnapshotRingBuffer(directory: folder, limit: 3)
        #expect(reopened.snapshots == buffer.snapshots)

        reopened.limit = 1
        #expect(reopened.snapshots.map(\.id) == [added[4].id])
        reopened.removeAll()
        #expect(SnapshotRingBuffer(directory: folder, limit: 3).snapshots.isEmpty)
    }
}

@Suite struct MotionWebhookTests {
    @Test func payloadUsesSnakeCaseForHomeAssistant() throws {
        let payload = MotionAlertPayload(
            source: "cameralab.security", personDetected: true, changedFraction: 0.05,
            time: Date(timeIntervalSince1970: 1_792_480_000), snapshotURL: "http://192.168.1.40:8081/snapshot.jpg?token=x"
        )
        let json = try #require(try JSONSerialization.jsonObject(with: MotionWebhook.encode(payload)) as? [String: Any])
        #expect(json["event"] as? String == "motion")
        #expect(json["person_detected"] as? Bool == true)
        #expect(json["changed_fraction"] as? Double == 0.05)
        #expect(json["snapshot_url"] as? String == "http://192.168.1.40:8081/snapshot.jpg?token=x")
        #expect((json["time"] as? String)?.hasPrefix("2026-") == true)
    }

    @Test func onlyAcceptsHTTPWebhookURLs() {
        #expect(MotionWebhook.validatedURL("https://ha.local:8123/api/webhook/homepad-motion") != nil)
        #expect(MotionWebhook.validatedURL("  http://192.168.1.10:8123/api/webhook/x  ") != nil)
        #expect(MotionWebhook.validatedURL("ftp://ha.local/x") == nil)
        #expect(MotionWebhook.validatedURL("not a url") == nil)
        #expect(MotionWebhook.validatedURL("") == nil)
    }
}
