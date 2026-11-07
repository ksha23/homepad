import AVFoundation
import HomePadCore

/// Plays the doorbell chime through the iPad when the doorbell rings, as HomeView
/// does, holding a `.playback` claim on the shared audio session only while it
/// sounds. With AirPods connected it plays in them.
///
/// It stays silent while Quiet Hours is on in Control Center, and in night mode
/// unless the person turned "Quiet in Night Mode" off, as intercom does. The
/// doorbell screen still appears either way.
@MainActor
final class DoorbellChime {
    static let owner = "smarthome.doorbellChime"
    /// Long enough for the display to wake and say whether it is night: the
    /// kiosk hears the same ring and a sleeping display reads `.sleeping` until then.
    private static let wakeDelay: Duration = .milliseconds(300)

    private let services: AppServices
    private var player: AVAudioPlayer?
    private var ringTask: Task<Void, Never>?
    /// Rendered once, off the main thread, at the first ring.
    private var sound: Data?
    private let log = Log.make("Doorbell")

    init(services: AppServices) {
        self.services = services
    }

    /// Whether a ring right now would stay silent.
    static func isQuiet(isOn: Bool, quietAtNight: Bool, quietHours: Bool, condition: DisplayCondition) -> Bool {
        !isOn || quietHours || (quietAtNight && condition == .night)
    }

    /// Chimes once for a ring. A second ring starts the chime again.
    func ring() {
        ringTask?.cancel()
        ringTask = Task { [weak self] in
            try? await Task.sleep(for: Self.wakeDelay)
            guard let self, !Task.isCancelled else { return }
            let settings = self.services.settings
            if Self.isQuiet(isOn: settings[SmartHomeSettings.doorbellChime],
                            quietAtNight: settings[SmartHomeSettings.doorbellChimeQuietAtNight],
                            quietHours: settings[CoreSettings.quietHoursEnabled],
                            condition: self.services.displayCondition) {
                self.log.info("Doorbell chime kept quiet")
                return
            }
            let sound = await self.renderedSound()
            guard !Task.isCancelled else { return }
            self.play(sound)
            try? await Task.sleep(for: .seconds(DoorbellChimeSound.duration + 0.2))
            guard !Task.isCancelled else { return }
            self.stopPlayer()
        }
    }

    /// Stops the chime, for when the doorbell screen closes.
    func stop() {
        ringTask?.cancel()
        ringTask = nil
        stopPlayer()
    }

    private func renderedSound() async -> Data {
        if let sound { return sound }
        let rendered = await Task.detached(priority: .userInitiated) { DoorbellChimeSound.wav() }.value
        sound = rendered
        return rendered
    }

    private func play(_ sound: Data) {
        stopPlayer()
        services.audioSession.claim(.playback, owner: Self.owner)
        do {
            let player = try AVAudioPlayer(data: sound, fileTypeHint: AVFileType.wav.rawValue)
            player.prepareToPlay()
            player.play()
            self.player = player
            log.info("Doorbell chime playing")
        } catch {
            log.error("Doorbell chime failed: \(error.localizedDescription, privacy: .public)")
            services.audioSession.release(owner: Self.owner)
        }
    }

    private func stopPlayer() {
        guard player != nil || services.audioSession.claims[Self.owner] != nil else { return }
        player?.stop()
        player = nil
        services.audioSession.release(owner: Self.owner)
    }
}
