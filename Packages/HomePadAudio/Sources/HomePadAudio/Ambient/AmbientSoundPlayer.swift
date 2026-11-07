import AVFoundation
import HomePadCore
import Observation

/// Plays generated sleep sounds through an output-only `AVAudioEngine`.
/// It never touches the engine's input node: the microphone belongs to
/// `services.microphone`. Sound follows the active route, so AirPods at night
/// or a HomePod on the nightstand both work.
@MainActor
@Observable
final class AmbientSoundPlayer: PlaybackSource {
    let kind = MediaSourceKind.system
    private(set) var sound: AmbientSound?
    private(set) var presetTitle: String?
    private(set) var volume: Double = 0.5
    private var playing = false
    private var fadeLevel = 1.0

    @ObservationIgnored private var engine: AVAudioEngine?
    @ObservationIgnored private let renderer = NoiseRenderer()
    @ObservationIgnored private var configurationObserver: NSObjectProtocol?
    @ObservationIgnored private var idleTask: Task<Void, Never>?
    private let log = Log.make("SleepSounds")

    var nowPlaying: NowPlaying? {
        guard let sound else { return nil }
        return NowPlaying(title: presetTitle ?? sound.title, artist: "Sleep Sounds", album: sound.title,
                          isPlaying: playing, source: .ambient)
    }

    var upNext: [QueueItem] { [] }
    var capabilities: PlaybackCapabilities { .live }

    /// Starts (or switches to) a sound. The audio session must already be claimed.
    func play(_ sound: AmbientSound, volume: Double, title: String? = nil) throws {
        idleTask?.cancel()
        self.sound = sound
        self.volume = volume
        presetTitle = title
        renderer.setSound(sound)
        try startEngine()
        playing = true
        applyGain()
        log.info("Sleep sound \(sound.rawValue, privacy: .public)")
    }

    func setVolume(_ volume: Double) {
        self.volume = max(0, min(1, volume))
        applyGain()
    }

    func resume() async throws {
        guard let sound else { return }
        try play(sound, volume: volume, title: presetTitle)
    }

    func pause() {
        playing = false
        applyGain()
        idleAfterFade { $0.pause() }
    }

    func stop() {
        playing = false
        sound = nil
        presetTitle = nil
        applyGain()
        idleAfterFade { engine in
            engine.stop()
        }
    }

    func skipForward() async {}
    func skipBackward() async {}
    func seek(to seconds: TimeInterval) {}

    func setFadeLevel(_ level: Double) {
        fadeLevel = max(0, min(1, level))
        applyGain()
    }

    // MARK: Engine

    private func applyGain() {
        renderer.setTargetGain(playing ? Float(volume * fadeLevel) : 0)
    }

    /// Lets the gain ramp reach silence before pausing or stopping, so there is no click.
    private func idleAfterFade(_ action: @escaping @MainActor (AVAudioEngine) -> Void) {
        idleTask?.cancel()
        idleTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled, let self, let engine = self.engine, !self.playing else { return }
            action(engine)
        }
    }

    private func startEngine() throws {
        let engine = self.engine ?? makeEngine()
        self.engine = engine
        guard !engine.isRunning else { return }
        engine.prepare()
        try engine.start()
    }

    private func makeEngine() -> AVAudioEngine {
        let engine = AVAudioEngine()
        let hardwareRate = engine.outputNode.outputFormat(forBus: 0).sampleRate
        let format = AVAudioFormat(standardFormatWithSampleRate: hardwareRate > 0 ? hardwareRate : 48_000, channels: 2)!
        let renderer = self.renderer
        let source = AVAudioSourceNode(format: format) { _, _, frameCount, bufferList in
            renderer.render(frameCount: frameCount, bufferList: bufferList)
            return noErr
        }
        engine.attach(source)
        engine.connect(source, to: engine.mainMixerNode, format: format)
        configurationObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.restartAfterRouteChange() }
        }
        return engine
    }

    /// Route changes (AirPods in, AirPlay picked) stop the engine. Restart if we were playing.
    private func restartAfterRouteChange() {
        guard playing else { return }
        do {
            try startEngine()
        } catch {
            log.error("Sleep sound restart failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}
