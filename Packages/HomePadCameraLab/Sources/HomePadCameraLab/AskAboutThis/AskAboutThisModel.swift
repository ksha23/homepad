import Foundation
import HomePadCore
import Observation
import UIKit

/// State for Ask About This: freeze a frame (or pick a photo), ask any AI
/// provider about it through `services.assistant`, and stream the answer.
@MainActor
@Observable
final class AskAboutThisModel {
    enum Phase: Equatable {
        case live
        case asking
        case answered
        case failed(String)
    }

    static let owner = "cameralab.ask"
    static let examples = [
        "What plant is this?",
        "Is this avocado ripe?",
        "How do I fix this?",
        "What can I cook with these?",
        "Read this label to me",
    ]

    private(set) var phase: Phase = .live
    /// The frozen picture, nil while the camera is live.
    private(set) var still: UIImage?
    private(set) var answer = ""
    private(set) var askedQuestion = ""
    var question = ""

    @ObservationIgnored private var jpeg: Data?
    @ObservationIgnored private var task: Task<Void, Never>?

    /// Freezes the current camera frame.
    func capture(with lab: CameraLab) async throws {
        let captured = try await lab.stills.grab(owner: Self.owner, title: CameraLabTool.ask.title)
        still = captured.image
        jpeg = captured.jpeg
    }

    /// Uses a photo from the library instead of the camera.
    func use(photo: UIImage) {
        guard let cgImage = photo.cgImage, let data = FrameEncoder.jpeg(from: cgImage, maxDimension: 1600) else { return }
        still = UIImage(data: data)
        jpeg = data
        answer = ""
        phase = .live
    }

    /// Asks `text` about the frozen picture, capturing one first if needed.
    func ask(_ text: String, lab: CameraLab) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        task?.cancel()
        askedQuestion = trimmed
        question = ""
        answer = ""
        phase = .asking
        task = Task {
            do {
                if jpeg == nil { try await capture(with: lab) }
                guard let jpeg else { throw CameraLabError.noFrame }
                let request = AssistantRequest(
                    text: Self.prompt(for: trimmed), images: [jpeg],
                    speakResponse: lab.services.settings[CameraLabSettings.speakAnswers], presentInOverlay: false
                )
                for try await event in lab.services.assistant.ask(request) {
                    switch event {
                    case .textDelta(let delta): answer += delta
                    case .finished(let fullText): if answer.isEmpty { answer = fullText }
                    default: break
                    }
                }
                phase = .answered
            } catch is CancellationError {
                return
            } catch {
                phase = .failed(error.localizedDescription)
            }
        }
    }

    /// Back to the live camera for another question.
    func retake(lab: CameraLab) {
        task?.cancel()
        lab.services.assistant.cancel()
        still = nil
        jpeg = nil
        answer = ""
        askedQuestion = ""
        phase = .live
    }

    /// Adds context so any provider answers in the right voice for a wall display.
    static func prompt(for question: String) -> String {
        "\(question)\n\nThe attached photo was just taken with the back camera of a HomePad display in this home. Answer briefly and concretely, in a few sentences, for someone standing in front of it."
    }
}
