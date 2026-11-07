import Foundation
import HomePadCore

/// While HomePad talks, listens for "stop" so a person can interrupt by voice.
/// Runs only when the microphone is already allowed and not paused for AirPlay.
@MainActor
final class BargeInMonitor {
    private let services: AppServices
    private var engine: (any TranscriptionEngine)?

    init(services: AppServices) {
        self.services = services
    }

    /// Starts listening. `speaking` returns the sentence HomePad is saying right now.
    func start(speaking: @escaping @MainActor () -> String, onStop: @escaping @MainActor () -> Void) async {
        guard engine == nil, SpeechPermissions.grantedWithoutPrompt,
              services.settings[CoreSettings.microphoneEnabled],
              services.audioSession.mode != .longFormPlayback else { return }
        let engine = TranscriptionEngineFactory.make(microphone: services.microphone)
        self.engine = engine
        do {
            try await engine.start { update in
                if BargeInDetector.isStopCommand(heard: update.text, speaking: speaking()) { onStop() }
            }
        } catch {
            self.engine = nil
        }
    }

    func stop() async {
        await engine?.stop()
        engine = nil
    }
}
