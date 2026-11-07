import Foundation
import LocalAuthentication

/// Face ID or the passcode through the system sheet, on the device this runs on.
@MainActor
enum OwnerVerification {
    /// On a HomePad, before a link is allowed. Like the gate's Use Face ID,
    /// an iPad without a passcode has nothing to check and is allowed.
    static func verify(reason: String) async -> Bool {
        let context = LAContext()
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            return error?.code == LAError.passcodeNotSet.rawValue
        }
        return (try? await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason)) ?? false
    }
}
