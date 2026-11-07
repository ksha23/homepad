#if os(iOS)
import AVFoundation
import HomePadObjC
import Observation

/// One shared microphone tap. iOS gives an app one input, so the wake word,
/// speech recognition, sound recognition (smoke alarms), music recognition
/// and intercom recording all subscribe here instead of running their own engines.
///
/// Handlers run on the audio render thread: copy what you need and hop off quickly.
///
///     let token = services.microphone.subscribe { buffer, time in analyzer.analyze(buffer, at: time.sampleTime) }
///     services.microphone.unsubscribe(token)
@MainActor
@Observable
public final class MicrophoneHub {
    public typealias Handler = @Sendable (AVAudioPCMBuffer, AVAudioTime) -> Void

    public private(set) var isRunning = false
    public private(set) var lastError: String?
    /// Smoothed input level 0...1 for meters and voice activity UI.
    public private(set) var level: Double = 0
    public private(set) var subscriberCount = 0

    /// Replaced on every start, see `startIfNeeded`.
    @ObservationIgnored private var engine = AVAudioEngine()
    @ObservationIgnored private let fanout = Fanout()
    @ObservationIgnored private let audioSession: AudioSessionCoordinator
    @ObservationIgnored private var retryTask: Task<Void, Never>?
    /// Paused on purpose (privacy switch, long-form AirPlay): interruptions never restart it.
    @ObservationIgnored private var isSuspended = false
    /// Failed starts retried since the last successful one.
    @ObservationIgnored private var startRetries = 0
    private let log = Log.make("Microphone")
    /// With `-HomePadAudioTrace YES`, starts, stops and interruptions.
    private let trace = DebugTrace(file: "audio-session-trace.txt", argument: "HomePadAudioTrace")
    private static let owner = "core.microphone"

    public init(audioSession: AudioSessionCoordinator) {
        self.audioSession = audioSession
        // The input can change under a running engine: AirPods connect, or a
        // spoken request moves the input to their microphone. The engine stops
        // then, so the tap is installed again in the new format.
        NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange, object: nil, queue: .main
        ) { [weak self] note in
            let changed = note.object as? AVAudioEngine
            MainActor.assumeIsolated {
                guard let self, changed === self.engine else { return }
                self.restartAfterConfigurationChange()
            }
        }
        // An interruption stops the engine without a configuration change, and
        // its end is not always reported. The wake word then heard nothing until
        // HomePad restarted, so capture restarts on the end and on a retry.
        NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification, object: nil, queue: .main
        ) { [weak self] note in
            let type = (note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt).flatMap(AVAudioSession.InterruptionType.init)
            MainActor.assumeIsolated { self?.handleInterruption(began: type == .began) }
        }
        // iPadOS 27 deprecates that notice and says when audio may resume with a
        // new one, which an interruption's end may only arrive as.
        if #available(iOS 27.0, *) {
            NotificationCenter.default.addObserver(
                forName: AVAudioSession.resumptionRecommendationNotification, object: nil, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.handleInterruption(began: false) }
            }
        }
    }

    /// The format buffers arrive in (the hardware input format).
    public var format: AVAudioFormat {
        engine.inputNode.outputFormat(forBus: 0)
    }

    @discardableResult
    public func subscribe(_ handler: @escaping Handler) -> UUID {
        let id = fanout.add(handler)
        subscriberCount = fanout.count
        startRetries = 0
        startIfNeeded()
        return id
    }

    public func unsubscribe(_ id: UUID) {
        fanout.remove(id)
        subscriberCount = fanout.count
        if fanout.count == 0 { stop() }
    }

    /// Stops capture without dropping subscribers (privacy toggle, long-form AirPlay).
    public func suspend() {
        isSuspended = true
        retryTask?.cancel()
        stop()
    }

    /// Resumes capture if anyone is subscribed.
    public func resume() {
        isSuspended = false
        startRetries = 0
        startIfNeeded()
    }

    private func handleInterruption(began: Bool) {
        guard fanout.count > 0, !isSuspended else { return }
        trace.log("microphone interruption \(began ? "began" : "ended")")
        retryTask?.cancel()
        if began {
            stop()
            retryTask = Task { [weak self] in
                for delay in [1, 3, 10] {
                    try? await Task.sleep(for: .seconds(delay))
                    guard let self, !Task.isCancelled, !self.isRunning, !self.isSuspended, self.fanout.count > 0 else { return }
                    self.startIfNeeded()
                }
            }
        } else {
            startRetries = 0
            startIfNeeded()
        }
    }

    /// Tries starting again shortly, at most three times until a start succeeds.
    private func scheduleRetry() {
        let delays = [0.5, 2.0, 5.0]
        guard startRetries < delays.count else { return }
        let delay = delays[startRetries]
        startRetries += 1
        retryTask?.cancel()
        retryTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard let self, !Task.isCancelled, !self.isRunning, !self.isSuspended, self.fanout.count > 0 else { return }
            self.startIfNeeded()
        }
    }

    private func restartAfterConfigurationChange() {
        guard isRunning else { return }
        log.info("Microphone input changed, restarting")
        stop()
        startIfNeeded()
    }

    private func startIfNeeded() {
        guard !isRunning, fanout.count > 0 else { return }
        audioSession.claim(.record, owner: Self.owner)
        guard audioSession.isRecordingAvailable else {
            lastError = "Microphone paused while music plays to AirPlay speakers."
            return
        }
        // A fresh engine each start. Right after the session changes (a spoken
        // request, an interruption) the old one can report an input format the
        // hardware no longer has, and a tap with it raises an exception, which
        // crashed HomePad. A bad moment now means a retry instead.
        engine = AVAudioEngine()
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else {
            lastError = "No microphone input available."
            trace.log("microphone has no input format yet")
            scheduleRetry()
            return
        }
        let fanout = self.fanout
        let tapFailure = HPCatchException {
            input.installTap(onBus: 0, bufferSize: 4096, format: format) { [weak self] buffer, time in
                fanout.deliver(buffer, time)
                let rms = Self.rms(buffer)
                Task { @MainActor in
                    guard let self else { return }
                    self.level = self.level * 0.7 + Double(rms) * 0.3
                }
            }
        }
        if let tapFailure {
            lastError = tapFailure.reason ?? tapFailure.name.rawValue
            log.error("Microphone tap failed: \(self.lastError ?? "", privacy: .public)")
            trace.log("microphone tap failed: \(lastError ?? "")")
            scheduleRetry()
            return
        }
        do {
            engine.prepare()
            try engine.start()
            isRunning = true
            startRetries = 0
            lastError = nil
            log.info("Microphone started")
            trace.log("microphone started")
        } catch {
            input.removeTap(onBus: 0)
            lastError = error.localizedDescription
            log.error("Microphone failed: \(error.localizedDescription, privacy: .public)")
            trace.log("microphone failed: \(error.localizedDescription)")
        }
    }

    private func stop() {
        guard isRunning else { return }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        isRunning = false
        level = 0
        audioSession.release(owner: Self.owner)
        log.info("Microphone stopped")
        trace.log("microphone stopped")
    }

    private nonisolated static func rms(_ buffer: AVAudioPCMBuffer) -> Float {
        guard let data = buffer.floatChannelData?[0], buffer.frameLength > 0 else { return 0 }
        var sum: Float = 0
        for i in 0..<Int(buffer.frameLength) { sum += data[i] * data[i] }
        return min(1, sqrt(sum / Float(buffer.frameLength)) * 8)
    }

    /// Thread-safe handler list used from the audio thread.
    private final class Fanout: @unchecked Sendable {
        private let lock = NSLock()
        private var handlers: [UUID: Handler] = [:]

        var count: Int { lock.withLock { handlers.count } }

        func add(_ handler: @escaping Handler) -> UUID {
            let id = UUID()
            lock.withLock { handlers[id] = handler }
            return id
        }

        func remove(_ id: UUID) {
            lock.withLock { handlers[id] = nil }
        }

        func deliver(_ buffer: AVAudioPCMBuffer, _ time: AVAudioTime) {
            let current = lock.withLock { Array(handlers.values) }
            for handler in current { handler(buffer, time) }
        }
    }
}
#endif
