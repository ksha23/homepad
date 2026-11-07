import AppIntents
import Foundation
import HomePadCore

/// The package's App Intents. The app target lists it in its own
/// `AppIntentsPackage` so the build extracts these intents' metadata.
public struct HomePadConnectIntents: AppIntentsPackage {}

/// Errors Siri and Shortcuts read out.
enum ConnectIntentError: Error, CustomLocalizedStringResourceConvertible {
    case notRunning
    case noHomePad
    case notFound(String)
    case failed(String)

    var localizedStringResource: LocalizedStringResource {
        switch self {
        case .notRunning: "HomePad is still starting. Try again in a moment."
        case .noHomePad: "None of your HomePads are reachable. Make sure this device is on the same Wi-Fi and paired."
        case .notFound(let what): "HomePad could not find \(what)."
        case .failed(let reason): "\(reason)"
        }
    }
}

/// What every intent needs: the shared services and the Connect runtime.
@MainActor
struct IntentContext {
    let services: AppServices
    let runtime: ConnectRuntime

    static func current() throws -> IntentContext {
        guard let services = AppServices.current, let runtime = ConnectRuntime.current else {
            throw ConnectIntentError.notRunning
        }
        return IntentContext(services: services, runtime: runtime)
    }

    /// Runs a command here on a HomePad, or on every HomePad from a companion.
    func perform(_ command: RemoteCommand) async throws {
        if runtime.isHomePad {
            try await CommandExecutor(services: services).execute(command)
        } else {
            do {
                try await runtime.remote.send(command)
            } catch {
                throw ConnectIntentError.noHomePad
            }
        }
    }
}
