import AVFoundation
import Speech

/// Microphone and speech recognition permission, requested only when a person
/// first talks to HomePad, never at launch.
@MainActor
enum SpeechPermissions {
    static var microphoneGranted: Bool {
        AVAudioApplication.shared.recordPermission == .granted
    }

    static var speechGranted: Bool {
        SFSpeechRecognizer.authorizationStatus() == .authorized
    }

    /// True when listening can start without showing a system prompt.
    /// The wake phrase only ever runs in this state.
    static var grantedWithoutPrompt: Bool {
        microphoneGranted && speechGranted
    }

    /// Asks for anything missing. Returns false if the person declined.
    static func request() async -> Bool {
        if AVAudioApplication.shared.recordPermission == .undetermined {
            _ = await AVAudioApplication.requestRecordPermission()
        }
        guard microphoneGranted else { return false }
        if SFSpeechRecognizer.authorizationStatus() == .notDetermined {
            _ = await requestSpeechAuthorization()
        }
        return speechGranted
    }

    /// Nonisolated so the system's background callback never runs as main-actor code.
    nonisolated private static func requestSpeechAuthorization() async -> SFSpeechRecognizerAuthorizationStatus {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0) }
        }
    }
}
