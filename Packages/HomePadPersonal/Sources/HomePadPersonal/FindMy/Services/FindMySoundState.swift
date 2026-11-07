import Foundation
import HomePadCore

/// What happened to the last Play Sound on a device, for its card.
enum FindMySoundState: Equatable, Sendable {
    case sending
    /// Home Assistant took the request at this time.
    case sent(Date, TrackedDevice.Source)
    /// It did not go out, with a sentence that says why.
    case failed(String)

    /// "Sound sent at 4:11. iCloud plays it for about two minutes."
    var message: String {
        switch self {
        case .sending:
            return "Sending"
        case .sent(let date, let source):
            let time = date.formatted(date: .omitted, time: .shortened)
            switch source {
            case .iCloud: return "Sound sent at \(time). The device plays it for about two minutes, or until someone stops it."
            case .companionApp: return "Alert sent at \(time). It rings once at full volume, even on silent."
            case .other: return "Sent at \(time)."
            }
        case .failed(let reason):
            return "Could not play a sound. \(reason)"
        }
    }

    /// Says why a sound did not go out, in plain words.
    static func reason(for error: Error) -> String {
        switch error {
        case SmartHomeError.notConnected:
            "Home Assistant is not connected right now."
        case SmartHomeError.requiresRecognizedMember:
            "Look at the screen so HomePad recognizes you first."
        case SmartHomeError.backend(let message):
            message.hasSuffix(".") ? message : message + "."
        default:
            error.localizedDescription
        }
    }
}
