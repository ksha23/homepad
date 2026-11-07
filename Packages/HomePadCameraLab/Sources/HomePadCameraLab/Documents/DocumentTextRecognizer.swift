import CoreGraphics
import Vision

/// Turns scanned pages into text with Vision's `RecognizeDocumentsRequest`
/// (new in iOS 26), which understands paragraphs, lists and tables instead of
/// returning loose lines. It falls back to `RecognizeTextRequest` when the
/// document model is unavailable, for example in some simulators.
enum DocumentTextRecognizer {
    static func text(from pages: [CGImage]) async throws -> String {
        var texts: [String] = []
        for page in pages {
            texts.append(try await text(from: page))
        }
        return texts.filter { !$0.isEmpty }.joined(separator: "\n\n")
    }

    static func text(from page: CGImage) async throws -> String {
        do {
            var request = RecognizeDocumentsRequest()
            request.textRecognitionOptions.useLanguageCorrection = true
            let documents = try await request.perform(on: page)
            return documents.map(\.document.text.transcript).joined(separator: "\n\n").trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            var request = RecognizeTextRequest()
            request.recognitionLevel = .accurate
            let lines = try await request.perform(on: page)
            return lines.compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n")
        }
    }
}
