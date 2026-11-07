import AVFoundation
import Observation

/// Records a short AAC clip with the watch microphone for intercom.
@MainActor
@Observable
final class WatchRecorder {
    var isRecording = false
    var error: String?

    @ObservationIgnored private var recorder: AVAudioRecorder?
    @ObservationIgnored private var startedAt: Date?
    /// True while `start` waits for the permission answer. The talk button calls
    /// `start` on every drag update, so without it one press made several recorders.
    @ObservationIgnored private var isStarting = false
    /// The finger lifted before recording began, so it should not begin.
    @ObservationIgnored private var stopRequested = false

    func start() async {
        guard !isRecording, !isStarting else { return }
        isStarting = true
        stopRequested = false
        defer { isStarting = false }
        error = nil
        guard await AVAudioApplication.requestRecordPermission() else {
            error = "Allow microphone access for HomePad in Settings."
            return
        }
        guard !stopRequested else { return }
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.record, mode: .default)
            try session.setActive(true)
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("watch-\(UUID().uuidString).m4a")
            let settings: [String: Any] = [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: 22_050,
                AVNumberOfChannelsKey: 1,
                AVEncoderBitRateKey: 32_000,
            ]
            let recorder = try AVAudioRecorder(url: url, settings: settings)
            recorder.record(forDuration: 20)
            self.recorder = recorder
            startedAt = Date()
            isRecording = true
        } catch {
            self.error = error.localizedDescription
        }
    }

    /// Stops and returns the clip and its length, or nil if it was too short.
    func stop() -> (url: URL, duration: TimeInterval)? {
        if isStarting { stopRequested = true }
        guard let recorder, let startedAt else { return nil }
        recorder.stop()
        try? AVAudioSession.sharedInstance().setActive(false)
        isRecording = false
        self.recorder = nil
        self.startedAt = nil
        let duration = min(Date().timeIntervalSince(startedAt), 20)
        return duration > 0.5 ? (recorder.url, duration) : nil
    }
}
