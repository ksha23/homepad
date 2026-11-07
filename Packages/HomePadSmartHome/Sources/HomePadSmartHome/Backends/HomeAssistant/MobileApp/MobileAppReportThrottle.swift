import Foundation

/// Decides which sensor values go to Home Assistant and when, so presence
/// flicker does not flood it or its history.
///
/// - Only values that differ from what Home Assistant last took are sent
///   (`MobileAppSensorState.differs(from:)`).
/// - The first change after a quiet spell goes at once, so an automation that
///   waits for someone to walk up runs right away.
/// - After a send, the next waits until `minimumInterval` has passed and then
///   takes the values as they are by then. Someone stepping in and out of view
///   within that time sends nothing, and a burst of changes is one request.
struct MobileAppReportThrottle {
    /// At most one update this often. Five seconds keeps a person moving at the
    /// edge of a proximity level to twelve updates a minute at worst.
    static let standardInterval: TimeInterval = 5
    var minimumInterval = standardInterval
    /// What Home Assistant last took for each sensor.
    private(set) var reported: [MobileAppSensor: MobileAppSensorState] = [:]
    private(set) var lastSendAt: Date?

    /// The values Home Assistant has not heard yet.
    func changes(in states: [MobileAppSensorState]) -> [MobileAppSensorState] {
        states.filter { state in
            guard let old = reported[state.sensor] else { return true }
            return state.differs(from: old)
        }
    }

    /// When the next update may go: `now`, or once the interval since the last one has passed.
    func earliestSend(now: Date) -> Date {
        guard let lastSendAt else { return now }
        return max(now, lastSendAt.addingTimeInterval(minimumInterval))
    }

    /// An update is on its way. The interval counts from here, whatever its answer.
    mutating func noteSending(at date: Date) {
        lastSendAt = date
    }

    /// Home Assistant took these values.
    mutating func noteReported(_ states: [MobileAppSensorState]) {
        for state in states { reported[state.sensor] = state }
    }

    /// Home Assistant forgot the device (registered again), so everything is news.
    mutating func reset() {
        reported = [:]
        lastSendAt = nil
    }
}
