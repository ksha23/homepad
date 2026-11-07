import HomePadCore
import SwiftUI

/// Live diagnostics: what the sensors see right now, for tuning and support.
struct LiveStatusSection: View {
    let presence: LivePresenceService
    @Environment(AppServices.self) private var services

    var body: some View {
        let snapshot = presence.snapshot
        let diagnostics = presence.diagnostics
        Section("Live Status") {
            LabeledContent("Duty Cycle", value: diagnostics.mode.title)
            LabeledContent("Sensor", value: diagnostics.backend?.title ?? "None")
            LabeledContent("Source", value: snapshot.source.title)
            LabeledContent("Distance", value: distanceText(diagnostics.rawDistanceMeters))
            LabeledContent("Proximity", value: snapshot.proximity.title)
            LabeledContent("Looking at Screen", value: snapshot.isLookingAtScreen ? "Yes" : "No")
            LabeledContent("People", value: "\(snapshot.peopleCount)")
            LabeledContent("Ambient Light", value: lightText(snapshot.ambientLight, lux: diagnostics.ambientLux))
            LabeledContent("Recognized", value: recognizedText(snapshot.recognizedMemberID))
            LabeledContent("Last Match", value: matchText(presence.recognition.lastDecision))
            LabeledContent("Frame Rate", value: String(format: "%.1f fps", diagnostics.framesPerSecond))
            LabeledContent("Thermal State", value: diagnostics.thermalState.title)
            LabeledContent("Hand Gesture", value: diagnostics.lastHandGesture?.title ?? "None")
            LabeledContent("Last Sound", value: presence.sounds.recentAlerts.first?.kind.title ?? "None")
            if let error = diagnostics.lastError {
                LabeledContent("Last Error", value: error)
            }
        }
        .monospacedDigit()
    }

    private func distanceText(_ meters: Double?) -> String {
        guard let meters else { return "Unknown" }
        return Measurement(value: meters, unit: UnitLength.meters)
            .formatted(.measurement(width: .abbreviated, usage: .asProvided, numberFormatStyle: .number.precision(.fractionLength(2))))
    }

    private func lightText(_ light: AmbientLight?, lux: Double?) -> String {
        guard let light else { return "Unknown" }
        guard let lux else { return light.rawValue.capitalized }
        return "\(light.rawValue.capitalized), about \(Int(lux.rounded())) lux"
    }

    private func recognizedText(_ id: UUID?) -> String {
        guard let id else { return "Nobody" }
        return services.household.members.first { $0.id == id }?.name ?? "Unknown member"
    }

    private func matchText(_ decision: MatchDecision?) -> String {
        switch decision {
        case .none: "None yet"
        case .member(let id, let score): "\(recognizedText(id)) (\(String(format: "%.2f", score)))"
        case .unknown(let best): "No match (best \(String(format: "%.2f", best)))"
        case .spoof: "Rejected, flat face"
        }
    }
}
