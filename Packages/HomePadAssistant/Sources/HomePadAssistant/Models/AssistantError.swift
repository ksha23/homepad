import Foundation

/// Errors the assistant reports to people. Messages are friendly and short
/// because they are shown in big type and may be spoken.
public enum AssistantError: LocalizedError, Sendable, Equatable {
    case noProvider
    case providerUnavailable(provider: String, reason: String)
    case http(status: Int, message: String)
    case badResponse(String)
    case streamError(String)
    case refused
    case microphoneDisabled
    case permissionDenied(String)
    case speechUnavailable(String)

    public var errorDescription: String? {
        switch self {
        case .noProvider:
            "No AI provider is set up yet. Add one in Settings, AI Assistant."
        case .providerUnavailable(let provider, let reason):
            "\(provider) is not available. \(reason)"
        case .http(let status, let message):
            Self.describe(status: status, message: message)
        case .badResponse(let detail):
            "The AI provider sent a response HomePad could not read. \(detail)"
        case .streamError(let message):
            message
        case .refused:
            "The model declined to answer that."
        case .microphoneDisabled:
            "The microphone is turned off in Control Center."
        case .permissionDenied(let what):
            "HomePad does not have permission to use \(what). You can allow it in the Settings app."
        case .speechUnavailable(let reason):
            reason
        }
    }

    /// True when another provider might succeed (network, quota, server trouble, bad key).
    public var allowsFailover: Bool {
        switch self {
        case .http(let status, _): status == 401 || status == 403 || status == 404 || status == 408 || status == 429 || status >= 500
        case .providerUnavailable, .streamError, .badResponse: true
        default: false
        }
    }

    private static func describe(status: Int, message: String) -> String {
        let detail = message.isEmpty ? "" : " \(message)"
        switch status {
        case 401, 403: return "The API key was not accepted.\(detail)"
        case 404: return "The model or address was not found.\(detail)"
        case 429: return "The provider is rate limiting requests. Try again in a moment.\(detail)"
        case 500...: return "The provider is having trouble right now.\(detail)"
        default: return "The request failed with status \(status).\(detail)"
        }
    }
}
