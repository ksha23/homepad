import AVFoundation
import Foundation
import HomePadCore
import Speech

/// Speech to text with SpeechAnalyzer and SpeechTranscriber (iPadOS 26 and
/// later). Fully on device. Downloads the language model the first time.
@MainActor
final class AnalyzerTranscriptionEngine: TranscriptionEngine {
    private let microphone: MicrophoneHub
    private let locale: Locale
    private var analyzer: SpeechAnalyzer?
    private var input: AsyncStream<AnalyzerInput>.Continuation?
    private var subscription: UUID?
    private var resultsTask: Task<Void, Never>?
    private var finalized = ""
    private var volatile = ""

    init(microphone: MicrophoneHub, locale: Locale) {
        self.microphone = microphone
        self.locale = locale
    }

    func start(onUpdate: @escaping @MainActor (TranscriptUpdate) -> Void) async throws {
        await stop()
        guard let supported = await SpeechTranscriber.supportedLocale(equivalentTo: locale) else {
            throw AssistantError.speechUnavailable("Speech recognition does not support this language yet.")
        }
        let transcriber = SpeechTranscriber(
            locale: supported, transcriptionOptions: [], reportingOptions: [.volatileResults, .fastResults], attributeOptions: []
        )
        if let installation = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
            try await installation.downloadAndInstall()
        }
        guard let format = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber]) else {
            throw AssistantError.speechUnavailable("Speech recognition is not ready on this iPad.")
        }
        let analyzer = SpeechAnalyzer(modules: [transcriber])
        try await analyzer.prepareToAnalyze(in: format)

        let (stream, continuation) = AsyncStream<AnalyzerInput>.makeStream(bufferingPolicy: .bufferingNewest(128))
        let converter = AudioBufferConverter(target: format)
        subscription = microphone.subscribe { buffer, _ in
            if let converted = converter.convert(buffer) {
                continuation.yield(AnalyzerInput(buffer: converted))
            }
        }
        input = continuation
        self.analyzer = analyzer
        try await analyzer.start(inputSequence: stream)

        resultsTask = Task { [weak self] in
            do {
                for try await result in transcriber.results {
                    self?.handle(String(result.text.characters), isFinal: result.isFinal, onUpdate: onUpdate)
                }
            } catch {
                Log.make("AssistantSpeech").error("Transcription ended: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    func stop() async {
        if let subscription { microphone.unsubscribe(subscription) }
        subscription = nil
        input?.finish()
        input = nil
        resultsTask?.cancel()
        resultsTask = nil
        await analyzer?.cancelAndFinishNow()
        analyzer = nil
        reset()
    }

    func reset() {
        finalized = ""
        volatile = ""
    }

    private func handle(_ text: String, isFinal: Bool, onUpdate: @MainActor (TranscriptUpdate) -> Void) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if isFinal {
            finalized = [finalized, trimmed].filter { !$0.isEmpty }.joined(separator: " ")
            volatile = ""
        } else {
            volatile = trimmed
        }
        let combined = [finalized, volatile].filter { !$0.isEmpty }.joined(separator: " ")
        onUpdate(TranscriptUpdate(text: combined, isFinal: isFinal))
    }
}
