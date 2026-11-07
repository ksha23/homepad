import Foundation

/// The `.custom` event that asks modules for the access sensing needs: Presence
/// requests the camera and microphone, the assistant speech recognition (for the
/// wake phrase). Shell posts it right after setup explains what is sensed.
public enum SensingPermissionRequest {
    public static let name = "core.requestSensingPermissions"
}

public extension HomePadEvent {
    /// Asks every module to request the permissions it senses with. No-op for
    /// permissions already granted or declined.
    static var requestSensingPermissions: HomePadEvent {
        .custom(name: SensingPermissionRequest.name, payload: .null)
    }
}
