import Foundation

/// Connection state of one backend, shown in Settings and the Home app.
enum BackendStatus: Equatable, Sendable {
    case notConfigured
    case connecting
    case connected(detail: String?)
    case reconnecting(retryAt: Date?)
    case failed(String)

    var isConnected: Bool {
        if case .connected = self { return true }
        return false
    }

    /// One short line for Settings.
    var summary: String {
        switch self {
        case .notConfigured: "Not set up"
        case .connecting: "Connecting"
        case .connected(let detail): detail.map { "Connected, \($0)" } ?? "Connected"
        case .reconnecting(let date):
            if let date, date > Date() {
                "Reconnecting \(date.formatted(.relative(presentation: .named)))"
            } else {
                "Reconnecting"
            }
        case .failed(let message): message
        }
    }
}
