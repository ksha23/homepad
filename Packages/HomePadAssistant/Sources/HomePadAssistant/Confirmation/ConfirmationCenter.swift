import Foundation
import Observation

/// Asks the person to approve a sensitive action ("Unlock the front door?")
/// and waits for a spoken yes or no, a tap, or an AirPods nod or shake.
/// Silence counts as no.
@MainActor
@Observable
public final class ConfirmationCenter {
    /// A question waiting for an answer.
    public struct Prompt: Identifiable, Equatable {
        public let id = UUID()
        public let question: String
    }

    public private(set) var pending: Prompt?
    /// Seconds before an unanswered question counts as no.
    static let timeout: Duration = .seconds(25)

    @ObservationIgnored private var continuation: CheckedContinuation<Bool, Never>?
    @ObservationIgnored private var timeoutTask: Task<Void, Never>?
    /// Called when a question appears, so voice can speak it and listen for the answer.
    @ObservationIgnored var onAsk: (@MainActor (Prompt) -> Void)?

    public init() {}

    /// Shows the question and returns the answer. A newer question cancels an older one.
    func confirm(_ question: String) async -> Bool {
        resolve(false)
        let prompt = Prompt(question: question)
        pending = prompt
        timeoutTask = Task { [weak self] in
            try? await Task.sleep(for: Self.timeout)
            if !Task.isCancelled { self?.resolve(false) }
        }
        return await withCheckedContinuation { continuation in
            self.continuation = continuation
            onAsk?(prompt)
        }
    }

    /// Answers the pending question. Taps, gestures and speech all end here.
    public func resolve(_ approved: Bool) {
        timeoutTask?.cancel()
        timeoutTask = nil
        pending = nil
        continuation?.resume(returning: approved)
        continuation = nil
    }

    /// Spoken answer. Returns false when the words were neither yes nor no.
    @discardableResult
    func resolve(spoken text: String) -> Bool {
        guard pending != nil, let answer = YesNoClassifier.classify(text) else { return false }
        resolve(answer)
        return true
    }
}
