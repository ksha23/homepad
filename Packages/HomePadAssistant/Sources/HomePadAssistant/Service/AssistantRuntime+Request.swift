import Foundation
import HomePadCore

extension AssistantRuntime {
    /// Runs one request: routing, tool loop, streaming into the session,
    /// speaking sentence by sentence, history, then follow-up or auto-dismiss.
    func run(_ request: AssistantRequest, isVoice: Bool, continuation: AsyncThrowingStream<AssistantEvent, Error>.Continuation?) {
        reset()
        var session = AssistantSession()
        session.isPresented = request.presentInOverlay
        session.transcript = request.text
        session.attachedImage = request.images.first
        session.isVoice = isVoice
        self.session = session
        phase = .thinking
        continuation?.yield(.transcript(request.text))

        requestTask = Task { [weak self] in
            await self?.perform(request, isVoice: isVoice, continuation: continuation)
        }
    }

    private func perform(_ request: AssistantRequest, isVoice: Bool, continuation: AsyncThrowingStream<AssistantEvent, Error>.Continuation?) async {
        let member = services.household.activeMember
        // Chats are private: a turn joins a person's history only once they are
        // recognized, never just because they were picked by hand. A module's
        // text task joins nobody's.
        let historyOwner = request.isSelfContained ? nil : services.household.unlockedMember?.id
        let candidates = router.candidates(requested: request.providerID ?? chatProviderOverride)
        AssistantTrace.trace.log("providers ready: \(candidates.map(\.descriptor.id)), Apple Intelligence: "
            + (AppleFoundationProvider.unavailableReason ?? "available"))
        guard !candidates.isEmpty else {
            // Nothing can answer. Say why and leave it on screen: ending quietly
            // flashed the overlay and went back to waiting, whatever was asked.
            let message = Self.noProviderMessage
            session.errorMessage = message
            session.needsSetup = true
            phase = .error
            endVoiceExchange()
            scheduleAutoDismiss(after: .seconds(20))
            continuation?.yield(.finished(fullText: message))
            continuation?.finish()
            return
        }

        let shouldSpeak = request.speakResponse && services.settings[AssistantSettings.speakResponses]
        // Someone asked here, and the answer shows in the overlay or the Assistant
        // app. Another module's request (recipe import, Ask About This) is not
        // about the screen.
        let isShownHere = continuation == nil || request.presentInOverlay
        var chunker = SentenceChunker()
        let emit: (AssistantEvent) -> Void = { [weak self] event in
            guard let self else { return }
            continuation?.yield(event)
            switch event {
            case .textDelta(let delta):
                self.session.answer += delta
                self.session.activity = nil
                if shouldSpeak {
                    chunker.append(delta).forEach(self.speech.enqueue)
                    self.phase = .speaking
                }
            case .card(let card):
                self.session.cards.append(card)
            default:
                break
            }
        }
        let cardOwner = toolContext.beginCards { card in emit(.card(card)) }
        defer { toolContext.endCards(owner: cardOwner) }

        // A text task gets no tools, so reading a flyer can never add the event
        // itself before the person has checked it.
        let tools = request.isSelfContained ? [] : availableTools()
        let engine = ConversationEngine(
            invoker: ToolInvoker(tools: tools, household: services.household, confirmations: confirmations,
                                 selfConfirmingTools: AssistantToolset.selfConfirming),
            emit: emit,
            onActivity: { [weak self] name in self?.session.activity = ToolActivity.describe(name) }
        )
        let input = ConversationEngine.Input(
            message: .user(request.text, images: request.images.map { ChatImage(data: $0) }),
            history: request.isSelfContained ? [] : conversations.contextMessages(for: historyOwner),
            tools: tools, candidates: candidates,
            system: { [weak self] descriptor in
                request.isSelfContained
                    ? Self.textTaskSystemPrompt
                    : self?.systemPrompt(for: descriptor, tools: tools, isShownHere: isShownHere) ?? ""
            }
        )

        do {
            let output = try await engine.run(input) { [weak self] descriptor in self?.session.providerName = descriptor.displayName }
            AssistantTrace.trace.log("\(output.provider.id) answered \"\(output.text)\"")
            for url in output.citations.uniqued().prefix(3) { emit(.card(CardFactory.link(url))) }
            if shouldSpeak, let rest = chunker.flush() { speech.enqueue(rest) }
            if !request.isSelfContained {
                conversations.append(
                    ConversationTurn(userText: request.text, assistantText: output.text, providerName: output.provider.displayName,
                                     hadImage: !request.images.isEmpty, actions: output.actions),
                    for: historyOwner
                )
            }
            // The bold marks are for HomePad's own answer view. Siri and Handoff get plain words.
            let plainText = isShownHere ? AnswerMarkdown.plain(output.text) : output.text
            advertiseForHandoff(prompt: request.text, answer: plainText, request: request, member: member)
            continuation?.yield(.finished(fullText: plainText))
            continuation?.finish()
            await finishSpeaking(isVoice: isVoice)
            // Dismissed or replaced while speaking: that already stopped
            // everything, so listening now would reopen what was just closed.
            guard !Task.isCancelled else { return }
            // With follow-ups on, HomePad listens after every spoken answer, as a
            // smart speaker does, unless music is playing now: an open microphone
            // would take lyrics for a request, and the wake word works over music.
            // A question is always worth an answer.
            // A question anywhere counts: "Can I do what, exactly? I can change the
            // music..." asks for a reply without ending on a question mark.
            let asked = output.text.contains("?")
            let musicPlaying = services.media.nowPlaying?.isPlaying == true
            if isVoice, services.settings[AssistantSettings.followUpListening], asked || !musicPlaying {
                AssistantTrace.trace.log("listening for a follow-up")
                beginListening(followUp: true)
            } else {
                endVoiceExchange()
                // A spoken answer was heard already: leave soon after, not 12 s later.
                scheduleAutoDismiss(after: isVoice ? .seconds(4) : .seconds(12))
            }
        } catch is CancellationError {
            continuation?.finish(throwing: CancellationError())
        } catch {
            if Task.isCancelled {
                continuation?.finish(throwing: CancellationError())
                return
            }
            AssistantTrace.trace.log("request failed: \(error.localizedDescription)")
            speech.stop()
            session.activity = nil
            session.errorMessage = error.localizedDescription
            session.needsSetup = (error as? AssistantError) == .noProvider
            phase = .error
            continuation?.finish(throwing: error)
            endVoiceExchange()
            scheduleAutoDismiss()
        }
    }

    /// Why no provider can answer, and what to do about it.
    static var noProviderMessage: String {
        guard let reason = AppleFoundationProvider.unavailableReason else {
            return AssistantError.noProvider.errorDescription ?? ""
        }
        return "\(reason) Or add a provider such as ChatGPT, Claude or Gemini in Settings, AI Assistant."
    }

    /// The whole system prompt of a self-contained text task
    /// (`AssistantRequest.isSelfContained`). The request's text says what to do,
    /// and nothing about the home or the person goes with it.
    static let textTaskSystemPrompt = """
        You turn text that a home display hands you into the structure its message asks for. \
        Follow the message's instructions exactly and reply with that structure only.
        """

    /// Registry tools, without personal ones unless the person is recognized.
    func availableTools() -> [AssistantTool] {
        let unlocked = services.household.isPersonalContentUnlocked
        return (registry?.tools ?? []).filter { !$0.requiresRecognizedMember || unlocked }
    }

    /// - Parameter isShownHere: Someone asked on this iPad, so what is on screen
    ///   counts, and the answer shows in HomePad's own view, which bolds key facts.
    func systemPrompt(for descriptor: ProviderDescriptor, tools: [AssistantTool], isShownHere: Bool) -> String {
        let household = services.household
        let preferences = household.activeMember.map(MemberAssistantPreferences.init(member:))
        let compact = descriptor.wireFormat == .appleOnDevice
        let weather = services.weather.current
        let context = PromptContext(
            now: Date(), timeZone: .current, locationName: weather?.locationName,
            weather: weather.map { "\(Int($0.temperature.rounded()))°\($0.unit == .celsius ? "C" : "F"), \($0.conditionText)" },
            memberName: household.activeMember?.name, aboutMember: preferences?.aboutMe,
            memberMemories: preferences?.memories ?? [],
            currentVolume: services.media.currentVolume,
            isPersonalUnlocked: household.isPersonalContentUnlocked,
            personality: preferences?.personality ?? services.settings[AssistantSettings.personality],
            homeLines: SystemPromptBuilder.homeLines(for: services.smartHome.accessories, compact: compact),
            toolNames: tools.map(\.name), compact: compact,
            // Personal screens count only for a recognized person, never one picked by hand.
            screen: isShownHere ? registry.flatMap {
                ScreenContextReader.describe(visibleAppID: services.visibleAppID, registry: $0,
                                             isPersonalUnlocked: household.unlockedMember != nil)
            } : nil,
            marksKeyFacts: isShownHere
        )
        return SystemPromptBuilder.build(context)
    }

    /// Waits for speech to end, listening for "stop" meanwhile when the request was spoken.
    private func finishSpeaking(isVoice: Bool) async {
        guard speech.isSpeaking else {
            phase = .idle
            return
        }
        phase = .speaking
        if isVoice {
            await bargeIn.start(speaking: { [weak self] in self?.speech.currentSentence ?? "" }) { [weak self] in
                self?.speech.stop()
            }
        }
        await speech.waitUntilDone()
        await bargeIn.stop()
        if phase == .speaking { phase = .idle }
    }

    /// Hides the answer after a while unless the person keeps interacting.
    func scheduleAutoDismiss(after delay: Duration = .seconds(12)) {
        dismissTask?.cancel()
        dismissTask = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled, let self, self.phase == .idle || self.phase == .error,
                  self.confirmations.pending == nil else { return }
            self.session.isPresented = false
        }
    }

    /// Offers a visible conversation to the iPad owner's other devices (Handoff, via Connect).
    /// Answers given to a recognized non-admin member are not offered, because Handoff
    /// reaches the devices of the iPad's Apple Account, not that member's.
    private func advertiseForHandoff(prompt: String, answer: String, request: AssistantRequest, member: HouseholdMember?) {
        guard request.presentInOverlay else { return }
        if services.household.isPersonalContentUnlocked, member?.isAdmin != true { return }
        services.events.post(.handoffAssistant(prompt: prompt, answer: answer))
    }
}
