import Foundation
@preconcurrency import HomeKit
import HomePadCore

/// One point of a sensor's history.
struct SensorSample: Hashable, Sendable {
    var date: Date
    var value: Double
}
