import CoreGraphics
import Foundation
import FoundationModels
import ImageIO

/// Apple's on-device model through Foundation Models. Private and free, and
/// only on iPads with Apple Intelligence turned on.
///
/// The framework runs its own tool loop, so tools are bridged with
/// `FoundationToolBridge` and executed through `request.executor`.
public struct AppleFoundationProvider: ChatProvider {
    public let config: ProviderConfig

    public init(config: ProviderConfig) {
        self.config = config
    }

    /// Nil when the model can be used, otherwise a short explanation.
    public static var unavailableReason: String? {
        switch SystemLanguageModel.default.availability {
        case .available: nil
        case .unavailable(.deviceNotEligible): "This iPad does not support Apple Intelligence."
        case .unavailable(.appleIntelligenceNotEnabled): "Turn on Apple Intelligence in the Settings app."
        case .unavailable(.modelNotReady): "The on-device model is still downloading."
        case .unavailable: "Apple Intelligence is not available right now."
        }
    }

    /// True when the on-device model accepts image attachments (iPadOS 27 and later).
    public static var supportsImages: Bool {
        if #available(iOS 27.0, *) {
            return SystemLanguageModel.default.capabilities.contains(.vision)
        }
        return false
    }

    public func stream(_ request: ChatRequest) -> AsyncThrowingStream<ChatStreamEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    if let reason = Self.unavailableReason {
                        throw AssistantError.providerUnavailable(provider: config.descriptor.displayName, reason: reason)
                    }
                    let tools: [any Tool] = try request.executor.map { executor in
                        try request.tools.map { try FoundationToolBridge(spec: $0, executor: executor) }
                    } ?? []
                    let session = LanguageModelSession(tools: tools, instructions: Self.instructions(for: request))
                    let latest = request.messages.last { $0.role == .user } ?? .user("")
                    var text = ""
                    for try await snapshot in Self.respond(session, to: latest) {
                        let current = snapshot.content
                        let delta = current.hasPrefix(text) ? String(current.dropFirst(text.count)) : current
                        text = current
                        if !delta.isEmpty { continuation.yield(.textDelta(delta)) }
                    }
                    continuation.yield(.completed(.assistant(text), .endTurn))
                    continuation.finish()
                } catch let error as LanguageModelSession.GenerationError {
                    continuation.finish(throwing: Self.translate(error))
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    public func listModels() async throws -> [String] {
        [config.descriptor.defaultModel]
    }

    /// The system prompt plus a short recap of earlier turns, since the session starts fresh each time.
    static func instructions(for request: ChatRequest) -> String {
        let earlier = request.messages.dropLast().suffix(6).compactMap { message -> String? in
            switch message.role {
            case .user: message.text.isEmpty ? nil : "User: \(message.text)"
            case .assistant: message.text.isEmpty ? nil : "Assistant: \(message.text)"
            case .tool: nil
            }
        }
        guard !earlier.isEmpty else { return request.system }
        return request.system + "\n\nRecent conversation:\n" + earlier.joined(separator: "\n")
    }

    private static func respond(
        _ session: LanguageModelSession, to message: ChatMessage
    ) -> LanguageModelSession.ResponseStream<String> {
        if #available(iOS 27.0, *), supportsImages {
            let images = message.images.compactMap { cgImage(from: $0.data) }
            if !images.isEmpty {
                return session.streamResponse {
                    message.text
                    for image in images { Attachment(image) }
                }
            }
        }
        return session.streamResponse(to: message.text)
    }

    private static func cgImage(from data: Data) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }

    private static func translate(_ error: LanguageModelSession.GenerationError) -> AssistantError {
        switch error {
        case .guardrailViolation, .refusal:
            .refused
        case .exceededContextWindowSize:
            .streamError("That was too much for the on-device model. Try a shorter request.")
        case .unsupportedLanguageOrLocale:
            .streamError("The on-device model does not support this language yet.")
        case .rateLimited, .concurrentRequests:
            .streamError("Apple Intelligence is busy. Try again in a moment.")
        default:
            .streamError(error.localizedDescription)
        }
    }
}
