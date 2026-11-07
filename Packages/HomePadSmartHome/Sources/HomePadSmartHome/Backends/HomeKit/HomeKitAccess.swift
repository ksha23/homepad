import Foundation
@preconcurrency import HomeKit
import HomePadCore
import Observation

/// Whether HomePad may read Apple Home.
enum HomeKitAccess: Equatable, Sendable {
    /// The person has not asked to connect Apple Home yet, so no prompt was shown.
    case notRequested
    case waiting
    case authorized
    case denied
    case restricted
}
