import Foundation
import HomePadCore
import Observation

/// HomePad's assistant: the `AssistantService` other modules call, plus the
/// state the overlay and the Assistant app show. Requests run through the
/// conversation engine, answers stream into `session` and are spoken.
@MainActor
@Observable
public final class AssistantRuntime: AssistantService {
    // MARK: AssistantService

    public internal(set) var phase: AssistantPhase = .idle
    public internal(set) var liveTranscript = ""
    public var activeProviderName: String {
        session.providerName ?? router.preferred?.displayName ?? "Not Set Up"
    }
    /// True when some provider is ready (a key is set or the on-device model is available).
    public var isConfigured: Bool {
        router.preferred != nil
    }

    // MARK: Shared state

    public internal(set) var session = AssistantSession()
    public let confirmations = ConfirmationCenter()
    public let conversations: ConversationStore
    /// Provider chosen in the Assistant app's switcher. Nil follows the usual order.
    public var chatProviderOverride: String?
    /// Which tab the Assistant app should show next time it opens.
    public var requestedAppTab: AssistantAppTab?

    @ObservationIgnored let services: AppServices
    @ObservationIgnored weak var registry: ModuleRegistry?
    @ObservationIgnored let speech: SpeechController
    @ObservationIgnored let wake: WakeWordMonitor
    @ObservationIgnored let bargeIn: BargeInMonitor
    @ObservationIgnored let toolContext: ToolContext
    @ObservationIgnored var requestTask: Task<Void, Never>?
    @ObservationIgnored var listenTask: Task<Void, Never>?
    @ObservationIgnored var listener: UtteranceListener?
    @ObservationIgnored var dismissTask: Task<Void, Never>?
    /// True from the moment a spoken exchange paused the iPad's music until it ends.
    @ObservationIgnored var holdsMediaForVoice = false
    @ObservationIgnored private var eventTask: Task<Void, Never>?

    /// Pass a `ConversationStore` without a directory to keep history in memory (previews and tests).
    public init(services: AppServices, registry: ModuleRegistry, conversations: ConversationStore? = nil) {
        self.services = services
        self.registry = registry
        let history = conversations ?? ConversationStore()
        self.conversations = history
        services.household.onMemberIDChange { [weak history] old, new in history?.moveMember(from: old, to: new) }
        self.toolContext = ToolContext(services: services, registry: registry, confirmations: confirmations)
        let providers = ProviderStore(settings: services.settings, keychain: services.keychain)
        self.speech = SpeechController(settings: services.settings, audioSession: services.audioSession) {
            let openAI = ProviderCatalog.openAI
            guard let key = providers.apiKey(for: openAI), let url = providers.baseURL(for: openAI) else { return nil }
            return (url, key)
        }
        self.wake = WakeWordMonitor(services: services)
        self.bargeIn = BargeInMonitor(services: services)
    }

    var providers: ProviderStore { ProviderStore(settings: services.settings, keychain: services.keychain) }
    var router: ProviderRouter { ProviderRouter(store: providers, household: services.household) }

    /// The generic tools to put in the registry.
    func makeTools() -> [AssistantTool] {
        AssistantToolset.make(toolContext)
    }

    /// Starts event handling and the wake phrase. Called once after all modules registered.
    func start() {
        confirmations.onAsk = { [weak self] prompt in self?.askAloud(prompt) }
        wake.isBusy = { [weak self] in self.map { $0.session.isPresented || $0.phase != .idle } ?? false }
        wake.onWake = { [weak self] in self?.wakeDetected() }
        wake.onPartial = { [weak self] text in self?.updateTranscript(text) }
        wake.onCommand = { [weak self] text in self?.submitVoice(text) }
        wake.begin()
        // Loads the Natural voice in the background when it is the chosen voice.
        speech.prepareNaturalVoice()
        VoiceCatalog.writeReportIfAsked()
        AssistantDemo.apply(to: self)
        eventTask = Task { [weak self] in
            guard let stream = self?.services.events.stream() else { return }
            for await event in stream { self?.handle(event) }
        }
    }

    private func handle(_ event: HomePadEvent) {
        switch event {
        case .invokeAssistant(let prompt):
            if let prompt, !prompt.isEmpty {
                submit(AssistantRequest(text: prompt), isVoice: false)
            } else {
                startListening()
            }
        case .headGesture(let gesture):
            if confirmations.pending != nil { confirmations.resolve(gesture == .nod) }
        case .custom(let name, let payload) where name == AssistantEventName.speak:
            if let text = payload.stringValue { announce(text) }
        case .custom(let name, _) where name == SensingPermissionRequest.name:
            // The wake phrase only listens with speech recognition allowed, and
            // nothing else asks for it before someone taps the mic button.
            Task { _ = await SpeechPermissions.request() }
        default:
            break
        }
    }

    // MARK: AssistantService

    public func ask(_ request: AssistantRequest) -> AsyncThrowingStream<AssistantEvent, Error> {
        let (stream, continuation) = AsyncThrowingStream<AssistantEvent, Error>.makeStream()
        run(request, isVoice: false, continuation: continuation)
        return stream
    }

    public func startListening() {
        beginListening(followUp: false)
    }

    public func stopListening() {
        listener?.finish()
    }

    /// Stops listening, speaking and answering. Any pending question counts as no.
    /// Music lowered for a spoken request comes back up.
    public func cancel() {
        reset()
        endVoiceExchange()
    }

    /// Stops listening, speaking and answering before the next step of the same
    /// exchange, keeping any music lowered for it.
    func reset() {
        listenTask?.cancel()
        listenTask = nil
        requestTask?.cancel()
        requestTask = nil
        dismissTask?.cancel()
        speech.stop()
        confirmations.resolve(false)
        liveTranscript = ""
        phase = .idle
    }

    /// Cancels everything and hides the overlay.
    public func dismiss() {
        cancel()
        session.isPresented = false
    }

    /// Stops talking but keeps the answer on screen (tap to interrupt).
    public func stopSpeaking() {
        speech.stop()
    }

    /// Opens the Assistant app on its settings, for the "add a provider" state.
    public func openSetup() {
        dismiss()
        requestedAppTab = .settings
        services.events.post(.openApp(id: AssistantModule.appID))
    }

    /// Sends typed or programmatic text, presenting the answer in the overlay.
    func submit(_ request: AssistantRequest, isVoice: Bool) {
        run(request, isVoice: isVoice, continuation: nil)
    }

    func updateTranscript(_ text: String) {
        liveTranscript = text
        session.transcript = text
    }
}

/// Tabs of the Assistant app.
public enum AssistantAppTab: String, Codable, Sendable {
    case chat, settings
}
