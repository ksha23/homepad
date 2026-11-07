import HomePadCore
import SwiftUI

/// What the kiosk sees and decides right now, for checking the setup.
struct KioskStatusSection: View {
    @Environment(AppServices.self) private var services
    @Environment(KioskController.self) private var kiosk: KioskController?

    var body: some View {
        Section("Right Now") {
            if let kiosk {
                LabeledContent("Display", value: kiosk.condition.title)
                LabeledContent("Presence", value: presenceText)
                LabeledContent("Power", value: powerText(kiosk.health))
                LabeledContent("Temperature", value: thermalText(kiosk.health.thermalState))
            } else {
                Text("Live status shows on the iPad running HomePad.").foregroundStyle(.secondary)
            }
        }
    }

    private var presenceText: String {
        let presence = services.presence
        guard presence.isRunning else { return "Sensing off" }
        let snapshot = presence.snapshot
        guard snapshot.isSomeonePresent else { return "Nobody nearby" }
        let distance = switch snapshot.proximity {
        case .near: "close by"
        case .mid: "across the table"
        case .far, .nobody: "across the room"
        }
        return snapshot.peopleCount > 1 ? "\(snapshot.peopleCount) people, nearest \(distance)" : "Someone \(distance)"
    }

    private func powerText(_ health: DeviceHealthMonitor) -> String {
        let level = health.batteryLevel.map { " at \(Int(($0 * 100).rounded()))%" } ?? ""
        switch health.power {
        case .charging: return "Charging\(level)"
        case .full: return "Fully charged"
        case .unplugged: return "On battery\(level)"
        case .unknown: return "Unknown"
        }
    }

    private func thermalText(_ state: ProcessInfo.ThermalState) -> String {
        switch state {
        case .nominal: "Normal"
        case .fair: "Warm"
        case .serious: "Hot, brightness reduced"
        case .critical: "Very hot, sensing paused"
        @unknown default: "Unknown"
        }
    }
}

extension DisplayCondition {
    /// A readable name for settings and the event log.
    var title: String {
        switch self {
        case .active: "In use"
        case .ambient: "Showing the face"
        case .dimmed: "Dimmed, nobody nearby"
        case .night: "Night mode"
        case .sleeping: "Sleeping"
        }
    }
}
