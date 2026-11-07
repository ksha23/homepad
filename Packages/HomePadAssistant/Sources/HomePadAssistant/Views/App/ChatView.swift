import HomePadCore
import HomePadUI
import SwiftUI

/// The conversation with the current person (or guest), plus the input bar.
struct ChatView: View {
    let runtime: AssistantRuntime
    let openSettings: () -> Void
    @Environment(AppServices.self) private var services

    var body: some View {
        // Whether a provider is ready reads every provider's key from the
        // keychain, so it is checked here, where the answer being streamed is
        // not read. `ChatTranscript` redraws with every streamed word.
        let hasProvider = !runtime.providers.readyProviders.isEmpty
        VStack(spacing: Theme.Spacing.m) {
            ChatTranscript(
                runtime: runtime, turns: runtime.conversations.turns(for: services.household.unlockedMember?.id),
                hasProvider: hasProvider, openSettings: openSettings
            )
            ChatInputBar(runtime: runtime)
                .disabled(!hasProvider)
        }
    }
}

/// Earlier turns, the answer being streamed, or an empty state.
private struct ChatTranscript: View {
    let runtime: AssistantRuntime
    let turns: [ConversationTurn]
    let hasProvider: Bool
    let openSettings: () -> Void

    var body: some View {
        if turns.isEmpty, !isAnswering {
            VStack(spacing: Theme.Spacing.m) {
                Spacer(minLength: 0)
                if hasProvider {
                    EmptyStateView("Ask Anything", message: "Type a question, attach a photo, or tap the microphone.", systemImage: "sparkles")
                } else {
                    EmptyStateView(
                        "Add an AI Provider",
                        message: "Use Apple Intelligence on this iPad, or add a key for ChatGPT, Claude, Gemini and more.",
                        systemImage: "sparkles", actionTitle: "Set Up", action: openSettings
                    )
                }
                Spacer(minLength: 0)
            }
        } else {
            transcript
        }
    }

    /// True while a typed request is being answered in the app (not the overlay).
    private var isAnswering: Bool {
        !runtime.session.isPresented && runtime.phase == .thinking && !runtime.session.transcript.isEmpty
    }

    private var transcript: some View {
        ScrollViewReader { reader in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: Theme.Spacing.l) {
                    ForEach(turns) { turn in
                        ChatTurnView(userText: turn.userText, answer: turn.assistantText, provider: turn.providerName, hadImage: turn.hadImage)
                    }
                    if isAnswering {
                        ChatTurnView(userText: runtime.session.transcript, answer: runtime.session.answer,
                                     provider: runtime.session.providerName ?? "", hadImage: runtime.session.attachedImage != nil,
                                     activity: runtime.session.answer.isEmpty ? (runtime.session.activity ?? "Thinking") : nil)
                        let sources = runtime.session.cards.filter { $0.kind == .link }
                        if !sources.isEmpty { SourceChipsView(cards: sources) }
                        ForEach(runtime.session.cards.filter { $0.kind != .link }) { AssistantCardView(card: $0) }
                    }
                    if !runtime.session.isPresented, let error = runtime.session.errorMessage {
                        Label(error, systemImage: "exclamationmark.triangle.fill").font(.title3).foregroundStyle(.yellow)
                    }
                    Color.clear.frame(height: 1).id("bottom")
                }
                .padding(.vertical, Theme.Spacing.m)
            }
            .scrollIndicators(.hidden)
            .defaultScrollAnchor(.bottom)
            .onChange(of: turns.count) { reader.scrollTo("bottom") }
            .onChange(of: runtime.session.answer) { reader.scrollTo("bottom") }
        }
    }
}
