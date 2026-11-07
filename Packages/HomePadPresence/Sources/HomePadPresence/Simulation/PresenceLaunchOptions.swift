import Foundation
import HomePadCore

/// Debug launch arguments for running Presence without camera hardware.
///
///     -HomePadSimulatePresence                cycle nobody, far, mid, near and back
///     -HomePadSimulatePresence near           hold one level (nobody, far, mid, near)
///     -HomePadSimulateSound smoke_alarm       fire a sound alert a few seconds after launch
///     -HomePadPresencePane status|enroll      with -HomePadSettingsPane presence: scroll to Live Status, or run enrollment
struct PresenceLaunchOptions: Sendable {
    /// Nil when presence is not simulated.
    var simulation: SimulatedPresenceScript.Mode?
    var simulatedSound: SoundAlertKind?
    var debugPane: DebugPane?

    enum DebugPane: String, Sendable {
        /// The settings pane scrolled to Live Status.
        case status
        case enroll
    }

    static let current = PresenceLaunchOptions(arguments: ProcessInfo.processInfo.arguments)

    init(arguments: [String]) {
        if let index = arguments.firstIndex(of: "-HomePadSimulatePresence") {
            let value = Self.value(after: index, in: arguments)
            simulation = value.flatMap(SimulatedPresenceScript.Mode.init(argument:)) ?? .cycle
        }
        if let label = Self.value(for: "-HomePadSimulateSound", in: arguments) {
            simulatedSound = SoundAlertKind.allCases.first { $0.eventLabel == label || $0.rawValue == label }
        }
        debugPane = Self.value(for: "-HomePadPresencePane", in: arguments).flatMap(DebugPane.init(rawValue:))
    }

    var isSimulated: Bool { simulation != nil }

    private static func value(for flag: String, in arguments: [String]) -> String? {
        arguments.firstIndex(of: flag).flatMap { value(after: $0, in: arguments) }
    }

    private static func value(after index: Int, in arguments: [String]) -> String? {
        let next = index + 1
        guard next < arguments.count, !arguments[next].hasPrefix("-") else { return nil }
        return arguments[next]
    }
}
