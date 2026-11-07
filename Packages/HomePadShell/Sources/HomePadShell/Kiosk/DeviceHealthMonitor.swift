import Foundation
import Observation
import UIKit

/// Watches power and heat, the two things that end an always-on display's day:
/// an unplugged iPad runs flat, and a hot one throttles and ages its battery.
@MainActor
@Observable
final class DeviceHealthMonitor {
    enum Power: Equatable {
        case charging, full, unplugged, unknown
    }

    private(set) var power: Power = .unknown
    /// Battery charge from 0 to 1, when known.
    private(set) var batteryLevel: Double?
    private(set) var thermalState: ProcessInfo.ThermalState = .nominal

    @ObservationIgnored private var observers: [NSObjectProtocol] = []

    /// - Parameter live: Start reading the real battery and thermal state.
    ///   Tests pass false and call `update`.
    init(live: Bool) {
        guard live else { return }
        UIDevice.current.isBatteryMonitoringEnabled = true
        readSystem()
        let center = NotificationCenter.default
        for name in [UIDevice.batteryStateDidChangeNotification, UIDevice.batteryLevelDidChangeNotification,
                     ProcessInfo.thermalStateDidChangeNotification] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.readSystem() }
            })
        }
    }

    /// True when the iPad runs on battery, which a kiosk should not.
    var isNotCharging: Bool { power == .unplugged }

    /// Highest brightness allowed for the current heat level.
    var brightnessCap: Double {
        switch thermalState {
        case .serious: 0.5
        case .critical: 0.3
        default: 1
        }
    }

    /// True when the iPad is hot enough that optional work should pause.
    var isOverheating: Bool { thermalState == .serious || thermalState == .critical }

    /// Overrides the readings (tests and the simulator's screenshot mode).
    func update(power: Power, batteryLevel: Double?, thermalState: ProcessInfo.ThermalState) {
        self.power = power
        self.batteryLevel = batteryLevel
        self.thermalState = thermalState
    }

    private func readSystem() {
        let device = UIDevice.current
        switch device.batteryState {
        case .charging: power = .charging
        case .full: power = .full
        case .unplugged: power = .unplugged
        default: power = .unknown
        }
        batteryLevel = device.batteryLevel >= 0 ? Double(device.batteryLevel) : nil
        thermalState = ProcessInfo.processInfo.thermalState
    }
}
