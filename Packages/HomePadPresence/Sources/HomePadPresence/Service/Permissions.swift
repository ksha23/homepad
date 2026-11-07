@preconcurrency import AVFoundation
import Foundation

/// Permission state without prompting.
enum PermissionStatus: Equatable, Sendable {
    case granted, denied, undetermined
}

/// Camera permission. Prompts only from a user action (lazy permissions).
enum CameraPermission {
    static var status: PermissionStatus {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: .granted
        case .notDetermined: .undetermined
        default: .denied
        }
    }

    static func request() async -> Bool {
        await AVCaptureDevice.requestAccess(for: .video)
    }
}

/// Microphone permission. Prompts only from a user action (lazy permissions).
enum MicrophonePermission {
    static var status: PermissionStatus {
        switch AVAudioApplication.shared.recordPermission {
        case .granted: .granted
        case .denied: .denied
        default: .undetermined
        }
    }

    static func request() async -> Bool {
        await AVAudioApplication.requestRecordPermission()
    }
}
