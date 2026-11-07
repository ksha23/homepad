#if os(iOS)
import AVFoundation
import HomePadCore

/// Records an intercom clip from the shared microphone into an AAC (.m4a) file.
/// It subscribes to `services.microphone` rather than running its own engine.
@MainActor
final class ClipRecorder {
    struct Clip {
        let url: URL
        let duration: TimeInterval
    }

    enum RecorderError: LocalizedError {
        case permissionDenied
        case microphoneUnavailable(String)

        var errorDescription: String? {
            switch self {
            case .permissionDenied: "HomePad needs microphone access for intercom. Turn it on in Settings."
            case .microphoneUnavailable(let reason): reason
            }
        }
    }

    private var token: UUID?
    private var writer: ClipWriter?
    private weak var microphone: MicrophoneHub?

    var isRecording: Bool { token != nil }

    /// Asks for microphone access the first time intercom is used.
    static func ensurePermission() async -> Bool {
        switch AVAudioApplication.shared.recordPermission {
        case .granted: true
        case .denied: false
        default: await AVAudioApplication.requestRecordPermission()
        }
    }

    func start(microphone: MicrophoneHub, maxSeconds: TimeInterval) throws {
        cancel()
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("intercom-\(UUID().uuidString).m4a")
        let writer = ClipWriter(url: url, maxSeconds: maxSeconds)
        self.writer = writer
        self.microphone = microphone
        token = microphone.subscribe { buffer, _ in writer.append(buffer) }
        if let error = microphone.lastError, !microphone.isRunning {
            cancel()
            throw RecorderError.microphoneUnavailable(error)
        }
    }

    /// Stops and returns the finished clip, or nil when nothing was captured.
    func stop() async -> Clip? {
        guard let writer else { return nil }
        unsubscribe()
        self.writer = nil
        return await writer.finish()
    }

    func cancel() {
        unsubscribe()
        if let writer {
            Task { _ = await writer.finish() }
        }
        writer = nil
    }

    private func unsubscribe() {
        if let token { microphone?.unsubscribe(token) }
        token = nil
    }
}

/// Writes copied microphone buffers to disk on its own queue, off the audio thread.
private final class ClipWriter: @unchecked Sendable {
    private let url: URL
    private let maxSeconds: TimeInterval
    private let queue = DispatchQueue(label: "homepad.intercom.writer")
    private var file: AVAudioFile?
    private var framesWritten: AVAudioFramePosition = 0
    private var sampleRate: Double = 0

    init(url: URL, maxSeconds: TimeInterval) {
        self.url = url
        self.maxSeconds = maxSeconds
    }

    /// Called on the audio render thread. Copies the buffer and returns at once.
    func append(_ buffer: AVAudioPCMBuffer) {
        guard let copy = buffer.copied() else { return }
        queue.async { self.write(copy) }
    }

    func finish() async -> ClipRecorder.Clip? {
        await withCheckedContinuation { continuation in
            queue.async {
                let duration = self.sampleRate > 0 ? Double(self.framesWritten) / self.sampleRate : 0
                self.file = nil   // closes and finalizes the AAC file
                continuation.resume(returning: duration > 0.3 ? ClipRecorder.Clip(url: self.url, duration: duration) : nil)
            }
        }
    }

    private func write(_ buffer: AVAudioPCMBuffer) {
        do {
            if file == nil {
                let format = buffer.format
                sampleRate = format.sampleRate
                let settings: [String: Any] = [
                    AVFormatIDKey: kAudioFormatMPEG4AAC,
                    AVSampleRateKey: format.sampleRate,
                    AVNumberOfChannelsKey: format.channelCount,
                    AVEncoderBitRateKey: 64_000,
                ]
                file = try AVAudioFile(forWriting: url, settings: settings, commonFormat: format.commonFormat,
                                       interleaved: format.isInterleaved)
            }
            guard Double(framesWritten) < maxSeconds * sampleRate else { return }
            try file?.write(from: buffer)
            framesWritten += AVAudioFramePosition(buffer.frameLength)
        } catch {
            Log.make("Intercom").error("Clip write failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}
#endif
