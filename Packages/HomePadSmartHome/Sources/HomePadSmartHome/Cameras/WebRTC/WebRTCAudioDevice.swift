import AVFoundation
import HomePadCore
import os
import WebRTC

/// WebRTC's sound, in and out, through HomePad's own audio instead of WebRTC's.
///
/// WebRTC's built-in device opens a voice processing I/O unit and sets the audio
/// session itself. That would take the one microphone input from `MicrophoneHub`
/// (the wake word, sound alerts, intercom), duck music, and fight
/// `AudioSessionCoordinator` over the category. Here, instead:
///
/// - Playout runs an `AVAudioEngine` of its own, only while some camera view is
///   unmuted, under a `.playback` claim. It mixes with music.
/// - Recording, for talk, subscribes to `MicrophoneHub` like every other
///   listener, only while WebRTC records (a talk track is on the sender).
///
/// WebRTC calls the `RTCAudioDevice` methods on one thread of its own. Engine and
/// microphone work hops to the main actor and never waits for it, so closing a
/// peer connection from the main thread cannot deadlock against this device.
final class WebRTCAudioDevice: NSObject, RTCAudioDevice, @unchecked Sendable {
    private struct State {
        var delegate: RTCAudioDeviceDelegate?
        var isPlayoutInitialized = false
        var isPlaying = false
        var isRecordingInitialized = false
        var isRecording = false
        /// Rates as WebRTC was told them. Playout keeps its rate for the engine's
        /// life, and recording follows the microphone's (`RecordPipe`).
        var outputSampleRate: Double
        var inputSampleRate: Double
    }

    private let state: OSAllocatedUnfairLock<State>
    private let playoutPipe: PlayoutPipe
    private let recordPipe: RecordPipe
    @MainActor private let playout: WebRTCPlayout
    @MainActor private let recording: WebRTCRecording

    @MainActor
    init(audioSession: AudioSessionCoordinator, microphone: MicrophoneHub) {
        let rate = Self.hardwareSampleRate
        state = OSAllocatedUnfairLock(initialState: State(outputSampleRate: rate, inputSampleRate: rate))
        let playoutPipe = PlayoutPipe()
        playoutPipe.sampleRate = rate
        let recordPipe = RecordPipe()
        self.playoutPipe = playoutPipe
        self.recordPipe = recordPipe
        playout = WebRTCPlayout(audioSession: audioSession, pipe: playoutPipe)
        recording = WebRTCRecording(microphone: microphone, pipe: recordPipe)
        super.init()
        recordPipe.onRateChange = { [weak self] rate in self?.inputRateChanged(to: rate) }
        recordPipe.onThreadChange = { [weak self] in self?.notify { $0.notifyAudioInputInterrupted() } }
        playout.onRestart = { [weak self] in self?.notify { $0.notifyAudioOutputInterrupted() } }
    }

    /// The rate the iPad's audio hardware runs at now. WebRTC resamples to it.
    private static var hardwareSampleRate: Double {
        AVAudioSession.sharedInstance().sampleRate
    }

    /// Whether this camera view wants its sound heard. The engine runs while any does.
    @MainActor
    func setAudible(_ audible: Bool, owner: ObjectIdentifier) {
        playout.setAudible(audible, owner: owner)
    }

    // MARK: RTCAudioDevice

    var deviceInputSampleRate: Double { state.withLock { $0.inputSampleRate } }
    var inputIOBufferDuration: TimeInterval { AVAudioSession.sharedInstance().ioBufferDuration }
    var inputNumberOfChannels: Int { 1 }
    var inputLatency: TimeInterval { AVAudioSession.sharedInstance().inputLatency }
    var deviceOutputSampleRate: Double { state.withLock { $0.outputSampleRate } }
    var outputIOBufferDuration: TimeInterval { AVAudioSession.sharedInstance().ioBufferDuration }
    var outputNumberOfChannels: Int { 1 }
    var outputLatency: TimeInterval { AVAudioSession.sharedInstance().outputLatency }

    var isInitialized: Bool { state.withLock { $0.delegate != nil } }

    func initialize(with delegate: RTCAudioDeviceDelegate) -> Bool {
        state.withLock { $0.delegate = delegate }
        playoutPipe.getPlayoutData = delegate.getPlayoutData
        recordPipe.deliver = delegate.deliverRecordedData
        return true
    }

    func terminateDevice() -> Bool {
        _ = stopPlayout()
        _ = stopRecording()
        state.withLock { $0.delegate = nil }
        return true
    }

    var isPlayoutInitialized: Bool { state.withLock { $0.isPlayoutInitialized } }

    func initializePlayout() -> Bool {
        let rate = Self.hardwareSampleRate
        state.withLock {
            $0.isPlayoutInitialized = true
            $0.outputSampleRate = rate
        }
        playoutPipe.sampleRate = rate
        return true
    }

    var isPlaying: Bool { state.withLock { $0.isPlaying } }

    func startPlayout() -> Bool {
        state.withLock { $0.isPlaying = true }
        onMain { $0.playout.setRequested(true) }
        return true
    }

    func stopPlayout() -> Bool {
        state.withLock {
            $0.isPlaying = false
            $0.isPlayoutInitialized = false
        }
        onMain { $0.playout.setRequested(false) }
        return true
    }

    var isRecordingInitialized: Bool { state.withLock { $0.isRecordingInitialized } }

    func initializeRecording() -> Bool {
        state.withLock { $0.isRecordingInitialized = true }
        recordPipe.expectedSampleRate = state.withLock { $0.inputSampleRate }
        return true
    }

    var isRecording: Bool { state.withLock { $0.isRecording } }

    func startRecording() -> Bool {
        state.withLock { $0.isRecording = true }
        onMain { $0.recording.start() }
        return true
    }

    func stopRecording() -> Bool {
        state.withLock {
            $0.isRecording = false
            $0.isRecordingInitialized = false
        }
        onMain { $0.recording.stop() }
        return true
    }

    // MARK: Helpers

    private func onMain(_ work: @escaping @MainActor (WebRTCAudioDevice) -> Void) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            MainActor.assumeIsolated { work(self) }
        }
    }

    /// The microphone runs at another rate than WebRTC was told (a route
    /// change). WebRTC reads the new rate on its own thread.
    private func inputRateChanged(to rate: Double) {
        state.withLock { $0.inputSampleRate = rate }
        recordPipe.expectedSampleRate = rate
        notify { $0.notifyAudioInputParametersChange() }
    }

    private func notify(_ call: @escaping (RTCAudioDeviceDelegate) -> Void) {
        guard let delegate = state.withLock({ $0.delegate }) else { return }
        delegate.dispatchAsync { call(delegate) }
    }
}

/// Pulls WebRTC's mixed playout into an `AVAudioSourceNode` on the render thread.
/// WebRTC hands out 16 bit mono samples, converted here to the engine's floats.
private final class PlayoutPipe: @unchecked Sendable {
    /// Set before the engine starts and left alone while it runs.
    var getPlayoutData: RTCAudioDeviceGetPlayoutDataBlock?
    /// The rate WebRTC was told, which the engine's source node runs at.
    var sampleRate: Double = 0
    /// Room for the largest slice the engine asks for in one go. Bigger requests come in pieces.
    private static let capacity = 4096
    private let scratch = UnsafeMutablePointer<Int16>.allocate(capacity: capacity)

    deinit { scratch.deallocate() }

    func render(isSilence: UnsafeMutablePointer<ObjCBool>, timestamp: UnsafePointer<AudioTimeStamp>,
                frameCount: AVAudioFrameCount, output: UnsafeMutablePointer<AudioBufferList>) -> OSStatus {
        let buffers = UnsafeMutableAudioBufferListPointer(output)
        guard let out = buffers.first?.mData?.assumingMemoryBound(to: Float.self) else { return noErr }
        let total = Int(frameCount)
        guard let getPlayoutData else {
            out.update(repeating: 0, count: total)
            isSilence.pointee = true
            return noErr
        }
        var done = 0
        while done < total {
            let chunk = min(total - done, Self.capacity)
            var flags = AudioUnitRenderActionFlags()
            var list = AudioBufferList(mNumberBuffers: 1, mBuffers: AudioBuffer(
                mNumberChannels: 1, mDataByteSize: UInt32(chunk * MemoryLayout<Int16>.size), mData: scratch))
            let status = getPlayoutData(&flags, timestamp, 0, UInt32(chunk), &list)
            guard status == noErr else {
                (out + done).update(repeating: 0, count: total - done)
                return status
            }
            for index in 0..<chunk {
                out[done + index] = Float(scratch[index]) / 32_768
            }
            done += chunk
        }
        return noErr
    }
}

/// Converts the microphone's buffers to the 16 bit mono WebRTC takes. `append`
/// runs on the microphone's tap thread, one buffer at a time.
private final class RecordPipe: @unchecked Sendable {
    private struct Shared {
        var deliver: RTCAudioDeviceDeliverRecordedDataBlock?
        var expectedSampleRate: Double = 0
        /// The tap thread's Mach port, which names the thread.
        var thread: mach_port_t?
    }

    private let shared = OSAllocatedUnfairLock(initialState: Shared())
    /// Only touched on the tap thread.
    private var samples: [Int16] = []
    var onRateChange: ((Double) -> Void)?
    var onThreadChange: (() -> Void)?

    var deliver: RTCAudioDeviceDeliverRecordedDataBlock? {
        get { shared.withLock { $0.deliver } }
        set { shared.withLock { $0.deliver = newValue } }
    }

    var expectedSampleRate: Double {
        get { shared.withLock { $0.expectedSampleRate } }
        set { shared.withLock { $0.expectedSampleRate = newValue } }
    }

    /// A new recording may run on a new tap thread.
    func reset() {
        shared.withLock { $0.thread = nil }
    }

    func append(_ buffer: AVAudioPCMBuffer, at time: AVAudioTime) {
        let frames = Int(buffer.frameLength)
        guard frames > 0 else { return }
        let rate = buffer.format.sampleRate
        let current = pthread_mach_thread_np(pthread_self())
        let (deliver, expectedRate, threadChanged) = shared.withLock { shared in
            let changed = shared.thread.map { $0 != current } ?? false
            shared.thread = current
            return (shared.deliver, shared.expectedSampleRate, changed)
        }
        guard let deliver else { return }
        // WebRTC expects one thread until told otherwise, and the rate it was told.
        if threadChanged { onThreadChange?() }
        guard expectedRate == rate else {
            onRateChange?(rate)
            return
        }
        if samples.count < frames { samples = [Int16](repeating: 0, count: frames) }
        Self.convert(buffer, into: &samples)
        samples.withUnsafeMutableBufferPointer { pointer in
            var list = AudioBufferList(mNumberBuffers: 1, mBuffers: AudioBuffer(
                mNumberChannels: 1, mDataByteSize: UInt32(frames * MemoryLayout<Int16>.size), mData: pointer.baseAddress))
            var flags = AudioUnitRenderActionFlags()
            var stamp = time.audioTimeStamp
            _ = deliver(&flags, &stamp, 1, UInt32(frames), &list, nil, nil)
        }
    }

    /// The first channel, as 16 bit samples.
    private static func convert(_ buffer: AVAudioPCMBuffer, into samples: inout [Int16]) {
        let frames = Int(buffer.frameLength)
        if let floats = buffer.floatChannelData?[0] {
            for index in 0..<frames {
                samples[index] = Int16(max(-1, min(1, floats[index])) * Float(Int16.max))
            }
        } else if let ints = buffer.int16ChannelData?[0] {
            for index in 0..<frames { samples[index] = ints[index] }
        } else {
            for index in 0..<frames { samples[index] = 0 }
        }
    }
}

/// The engine that plays camera sound. Runs only while WebRTC plays and some view
/// is unmuted, so a wall of muted feeds never holds the audio session.
@MainActor
private final class WebRTCPlayout {
    private let audioSession: AudioSessionCoordinator
    private let pipe: PlayoutPipe
    private var engine: AVAudioEngine?
    private var configurationObserver: NSObjectProtocol?
    private var isRequested = false
    private var audibleOwners: Set<ObjectIdentifier> = []
    private let log = Log.make("CameraAudio")
    /// Each engine renders on a new thread, which WebRTC must hear about.
    var onRestart: (() -> Void)?

    private static let owner = "smarthome.camera.sound"

    init(audioSession: AudioSessionCoordinator, pipe: PlayoutPipe) {
        self.audioSession = audioSession
        self.pipe = pipe
    }

    func setRequested(_ requested: Bool) {
        isRequested = requested
        update()
    }

    func setAudible(_ audible: Bool, owner: ObjectIdentifier) {
        if audible { audibleOwners.insert(owner) } else { audibleOwners.remove(owner) }
        update()
    }

    private func update() {
        let shouldRun = isRequested && !audibleOwners.isEmpty
        if shouldRun, engine == nil {
            start()
        } else if !shouldRun, engine != nil {
            stop()
        }
    }

    private func start() {
        guard let format = AVAudioFormat(standardFormatWithSampleRate: pipe.sampleRate, channels: 1) else { return }
        audioSession.claim(.playback, owner: Self.owner)
        let engine = AVAudioEngine()
        let pipe = self.pipe
        let source = AVAudioSourceNode(format: format) { isSilence, timestamp, frameCount, output in
            pipe.render(isSilence: isSilence, timestamp: timestamp, frameCount: frameCount, output: output)
        }
        engine.attach(source)
        engine.connect(source, to: engine.mainMixerNode, format: format)
        do {
            engine.prepare()
            try engine.start()
        } catch {
            log.error("Camera sound could not start: \(error.localizedDescription, privacy: .public)")
            audioSession.release(owner: Self.owner)
            return
        }
        self.engine = engine
        onRestart?()
        // A category change (a spoken request, talk) stops the engine without a word.
        configurationObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.stop()
                self?.update()
            }
        }
    }

    private func stop() {
        if let configurationObserver { NotificationCenter.default.removeObserver(configurationObserver) }
        configurationObserver = nil
        engine?.stop()
        engine = nil
        audioSession.release(owner: Self.owner)
    }
}

/// Feeds the microphone to WebRTC while it records (someone holds Talk).
@MainActor
private final class WebRTCRecording {
    private let microphone: MicrophoneHub
    private let pipe: RecordPipe
    private var token: UUID?

    init(microphone: MicrophoneHub, pipe: RecordPipe) {
        self.microphone = microphone
        self.pipe = pipe
    }

    func start() {
        guard token == nil else { return }
        pipe.reset()
        let pipe = self.pipe
        token = microphone.subscribe { buffer, time in pipe.append(buffer, at: time) }
    }

    func stop() {
        guard let token else { return }
        microphone.unsubscribe(token)
        self.token = nil
    }
}
