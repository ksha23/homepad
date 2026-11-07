import Foundation
@preconcurrency import HomeKit
import HomePadCore
import Observation

/// One HomeKit home, for the home picker.
struct HomeKitHomeSummary: Identifiable, Hashable, Sendable {
    var id: String
    var name: String
}
