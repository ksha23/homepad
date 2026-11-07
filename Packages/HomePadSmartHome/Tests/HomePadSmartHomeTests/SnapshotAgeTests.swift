import Foundation
import Testing
@testable import HomePadSmartHome

/// The age label on a camera snapshot, as HomeView writes it.
@Suite("Snapshot age")
struct SnapshotAgeTests {
    private let now = Date(timeIntervalSinceReferenceDate: 800_000_000)
    private let english = Locale(identifier: "en_US")

    private func age(_ seconds: TimeInterval) -> String {
        SnapshotAge.text(capturedAt: now.addingTimeInterval(-seconds), now: now, locale: english)
    }

    @Test func aFreshSnapshotIsNow() {
        #expect(age(0) == "Now")
        #expect(age(59) == "Now")
    }

    @Test func olderOnesCountMinutesHoursAndDays() {
        #expect(age(60) == "1m ago")
        #expect(age(125) == "2m ago")
        #expect(age(3 * 3600 + 10) == "3h ago")
        #expect(age(2 * 86_400 + 10) == "2d ago")
    }
}
