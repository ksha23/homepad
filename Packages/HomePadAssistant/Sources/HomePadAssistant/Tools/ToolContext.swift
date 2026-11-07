import Foundation
import HomePadCore

/// What the assistant's own tools can reach. Services are looked up at call
/// time because later modules may replace them.
@MainActor
final class ToolContext {
    private weak var servicesRef: AppServices?
    private weak var registryRef: ModuleRegistry?
    let confirmations: ConfirmationCenter
    /// Where cards go for the request that is running, so tools can attach them to the answer.
    private var cardSink: ((AssistantCard) -> Void)?
    private var sinkOwner: UUID?

    init(services: AppServices, registry: ModuleRegistry, confirmations: ConfirmationCenter) {
        self.servicesRef = services
        self.registryRef = registry
        self.confirmations = confirmations
    }

    var services: AppServices {
        get throws {
            guard let servicesRef else { throw ToolError("HomePad is shutting down.") }
            return servicesRef
        }
    }

    var registry: ModuleRegistry? { registryRef }

    func emit(_ card: AssistantCard) {
        cardSink?(card)
    }

    /// Routes cards to one request. Returns a token for `endCards(owner:)`.
    func beginCards(_ sink: @escaping (AssistantCard) -> Void) -> UUID {
        let owner = UUID()
        cardSink = sink
        sinkOwner = owner
        return owner
    }

    /// Stops routing cards, unless a newer request already took over.
    func endCards(owner: UUID) {
        guard sinkOwner == owner else { return }
        cardSink = nil
        sinkOwner = nil
    }
}

/// A tool failure with a message the model can relay.
struct ToolError: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}
