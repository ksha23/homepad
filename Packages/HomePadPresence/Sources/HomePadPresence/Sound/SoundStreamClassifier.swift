@preconcurrency import AVFoundation
import Foundation
@preconcurrency import SoundAnalysis

/// Runs Apple's built-in sound classifier on microphone buffers.
///
/// Buffers arrive on the audio render thread from `MicrophoneHub`. They are
/// copied and analyzed on a private serial queue, because
/// `SNAudioStreamAnalyzer` is not thread-safe and the render thread must
/// never block. Only labels HomePad cares about are reported.
final class SoundStreamClassifier: NSObject, SNResultsObserving, @unchecked Sendable {
    /// Called on the analysis queue with a mapped kind and its confidence.
    var onDetection: ((SoundAlertKind, Double) -> Void)?

    private let queue = DispatchQueue(label: "com.homepad.presence.sound", qos: .utility)
    private var analyzer: SNAudioStreamAnalyzer?
    private var format: AVAudioFormat?
    /// Classifier hits below this are ignored before debouncing.
    private let floor = 0.3

    /// Hands a buffer to the classifier. Safe to call from the audio thread.
    func append(_ buffer: AVAudioPCMBuffer, at time: AVAudioTime) {
        guard let copy = buffer.copied() else { return }
        let position = time.sampleTime
        queue.async { [self] in
            if analyzer == nil || format != copy.format { makeAnalyzer(for: copy.format) }
            analyzer?.analyze(copy, atAudioFramePosition: position)
        }
    }

    /// Drops the analyzer (when listening stops).
    func reset() {
        queue.async { [self] in
            analyzer?.completeAnalysis()
            analyzer = nil
            format = nil
        }
    }

    private func makeAnalyzer(for format: AVAudioFormat) {
        let analyzer = SNAudioStreamAnalyzer(format: format)
        do {
            let request = try SNClassifySoundRequest(classifierIdentifier: .version1)
            try analyzer.add(request, withObserver: self)
            self.analyzer = analyzer
            self.format = format
        } catch {
            self.analyzer = nil
        }
    }

    // MARK: SNResultsObserving

    func request(_ request: SNRequest, didProduce result: SNResult) {
        guard let result = result as? SNClassificationResult else { return }
        for classification in result.classifications where classification.confidence >= floor {
            if let kind = SoundAlertKind.kind(forClassifierLabel: classification.identifier) {
                onDetection?(kind, classification.confidence)
            }
        }
    }

    func request(_ request: SNRequest, didFailWithError error: Error) {
        queue.async { [self] in analyzer = nil }
    }
}
