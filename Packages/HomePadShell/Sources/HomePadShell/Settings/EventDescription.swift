import HomePadCore

/// One-line descriptions of bus events for the event log.
enum EventDescription {
    static func text(for event: HomePadEvent) -> String {
        switch event {
        case .doorbellRang(let cameraID): "doorbellRang \(cameraID)"
        case .accessoryAlert(let accessoryID, let message): "accessoryAlert \(accessoryID): \(message)"
        case .presenceChanged(let snapshot):
            "presenceChanged present=\(snapshot.isSomeonePresent) people=\(snapshot.peopleCount) proximity=\(snapshot.proximity)"
        case .memberRecognized(let id): "memberRecognized \(id.uuidString.prefix(8))"
        case .gesture(let gesture): "gesture \(gesture.rawValue)"
        case .headGesture(let gesture): "headGesture \(gesture.rawValue)"
        case .soundDetected(let label, let confidence): "soundDetected \(label) \(Int(confidence * 100))%"
        case .motionDetected(let source): "motionDetected \(source)"
        case .timerFinished(_, let label): "timerFinished \(label)"
        case .intercomReceived(let from, let text): "intercomReceived from \(from)\(text.map { ": \($0)" } ?? "")"
        case .handoffReceived(let activityType, _): "handoffReceived \(activityType)"
        case .openApp(let id): "openApp \(id)"
        case .showFace(let id): "showFace \(id)"
        case .invokeAssistant(let prompt): "invokeAssistant\(prompt.map { " \($0)" } ?? "")"
        case .wake: "wake"
        case .goAmbient: "goAmbient"
        case .custom(let name, let payload): "custom \(name) \(payload.jsonString())"
        }
    }
}
