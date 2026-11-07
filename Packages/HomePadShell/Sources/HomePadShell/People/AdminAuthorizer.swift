import HomePadCore
import LocalAuthentication

/// Result of asking the device owner to prove who they are.
enum AuthorizationOutcome: Equatable {
    case allowed
    /// The iPad has no passcode, so nothing could be checked. Allowed, with a warning.
    case allowedWithoutPasscode
    case denied(String)

    var isAllowed: Bool {
        switch self {
        case .allowed, .allowedWithoutPasscode: true
        case .denied: false
        }
    }
}

/// Face ID or passcode through the system sheet (LocalAuthentication).
@MainActor
enum DeviceOwnerAuthentication {
    static func verify(reason: String) async -> AuthorizationOutcome {
        let context = LAContext()
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            if error?.code == LAError.passcodeNotSet.rawValue {
                return .allowedWithoutPasscode
            }
            return .denied(error?.localizedDescription ?? "Face ID and passcode are not available.")
        }
        do {
            let ok = try await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason)
            return ok ? .allowed : .denied("Not verified.")
        } catch let laError as LAError where laError.code == .userCancel || laError.code == .appCancel || laError.code == .systemCancel {
            return .denied("Cancelled.")
        } catch {
            return .denied(error.localizedDescription)
        }
    }
}

/// Decides whether the person at the screen may do admin things (open admin
/// settings panes, add, edit or remove people).
@MainActor
enum AdminAuthorizer {
    /// Allowed without asking when nobody is an admin yet (first-time setup) or
    /// when a recognized admin is in front of the screen. Otherwise asks for
    /// Face ID or the passcode.
    static func authorize(household: Household, reason: String) async -> AuthorizationOutcome {
        if canSkipVerification(household) { return .allowed }
        return await DeviceOwnerAuthentication.verify(reason: reason)
    }

    static func canSkipVerification(_ household: Household) -> Bool {
        if !household.members.contains(where: \.isAdmin) { return true }
        return household.isPersonalContentUnlocked && household.activeMember?.isAdmin == true
    }
}
