import AVFoundation
import HomePadCore
import Observation
import ShazamKit

/// "What's this song?" with ShazamKit, fed from the shared microphone tap.
/// It never opens its own input: buffers come from `services.microphone`.
@MainActor
@Observable
final class SongRecognizer {
    enum Phase: Equatable {
        case idle
        case listening
        case matched(SongMatch)
        case failed(String)
    }

    private(set) var phase: Phase = .idle
    @ObservationIgnored private unowned let services: AppServices
    static let listenTimeout: TimeInterval = 15

    init(services: AppServices) {
        self.services = services
    }

    var isListening: Bool { phase == .listening }

    /// Listens for up to 15 seconds and returns the match. The result also shows as a card.
    @discardableResult
    func identify() async -> Result<SongMatch, AudioError> {
        guard !isListening else { return .failure(.recognitionFailed("Already listening.")) }
        let result = await listen()
        switch result {
        case .success(let match): phase = .matched(match)
        case .failure(let error): phase = .failed(error.errorDescription ?? "I couldn't recognize that song.")
        }
        return result
    }

    func dismiss() {
        if !isListening { phase = .idle }
    }

    /// Shows a fixed result for simulator screenshots.
    func showDemo(_ match: SongMatch) {
        phase = .matched(match)
    }

    private func listen() async -> Result<SongMatch, AudioError> {
        guard services.settings[CoreSettings.microphoneEnabled] else {
            return .failure(.microphoneUnavailable("The microphone is turned off. Turn it on in Control Center to identify songs."))
        }
        guard await Self.hasMicrophonePermission() else { return .failure(.microphoneDenied) }
        guard services.audioSession.mode != .longFormPlayback else {
            return .failure(.microphoneUnavailable(
                "I can't listen while music plays to AirPlay speakers. Pause the music, or turn on Keep Microphone On in Audio settings."
            ))
        }

        phase = .listening
        let session = SHSession()
        let delegate = MatchDelegate()
        session.delegate = delegate
        let feeder = BufferFeeder(session: session)
        let token = services.microphone.subscribe { buffer, time in feeder.feed(buffer, at: time) }
        defer { services.microphone.unsubscribe(token) }
        guard services.microphone.isRunning else {
            return .failure(.microphoneUnavailable(services.microphone.lastError ?? "The microphone isn't available right now."))
        }

        let result = await withCheckedContinuation { (continuation: CheckedContinuation<Result<SongMatch, AudioError>, Never>) in
            let once = ResumeOnce(continuation)
            delegate.onMatch = { once.resume(.success($0)) }
            delegate.onError = { once.resume(.failure(.recognitionFailed($0))) }
            Task {
                try? await Task.sleep(for: .seconds(Self.listenTimeout))
                once.resume(.failure(.recognitionFailed("I couldn't recognize that song. Try again a little closer to the music.")))
            }
        }
        withExtendedLifetime(delegate) {}
        return result
    }

    private static func hasMicrophonePermission() async -> Bool {
        switch AVAudioApplication.shared.recordPermission {
        case .granted: return true
        case .denied: return false
        default: return await AVAudioApplication.requestRecordPermission()
        }
    }
}

extension SongMatch {
    init?(_ match: SHMatch) {
        guard let item = match.mediaItems.first, let title = item.title else { return nil }
        self.init(title: title, artist: item.artist, artworkURL: item.artworkURL, appleMusicID: item.appleMusicID,
                  appleMusicURL: item.appleMusicURL, webURL: item.webURL)
    }
}

/// Passes microphone buffers to ShazamKit from the audio thread.
private final class BufferFeeder: @unchecked Sendable {
    private let session: SHSession
    init(session: SHSession) { self.session = session }
    func feed(_ buffer: AVAudioPCMBuffer, at time: AVAudioTime) {
        session.matchStreamingBuffer(buffer, at: time)
    }
}

/// Receives ShazamKit callbacks on its own queue.
private final class MatchDelegate: NSObject, SHSessionDelegate, @unchecked Sendable {
    var onMatch: ((SongMatch) -> Void)?
    var onError: ((String) -> Void)?

    func session(_ session: SHSession, didFind match: SHMatch) {
        if let song = SongMatch(match) { onMatch?(song) }
    }

    func session(_ session: SHSession, didNotFindMatchFor signature: SHSignature, error: (any Error)?) {
        // Without an error this only means "not yet". Keep listening until the timeout.
        if let error { onError?(error.localizedDescription) }
    }
}

/// Resumes a continuation exactly once, from whichever callback arrives first.
private final class ResumeOnce<Value: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Value, Never>?

    init(_ continuation: CheckedContinuation<Value, Never>) {
        self.continuation = continuation
    }

    func resume(_ value: Value) {
        let pending = lock.withLock { () -> CheckedContinuation<Value, Never>? in
            defer { continuation = nil }
            return continuation
        }
        pending?.resume(returning: value)
    }
}
