import HomePadCore
import HomePadUI
import SwiftUI

/// The Siri-style assistant layer above everything: glowing edge, orb, live
/// transcript, big streaming answer, cards, confirmation prompts and a
/// follow-up microphone. Empty when the assistant is idle.
struct AssistantOverlayView: View {
    @Environment(AppServices.self) private var services

    var body: some View {
        let runtime = services.assistant as? AssistantRuntime
        ZStack {
            if let runtime, runtime.session.isPresented {
                AssistantOverlayContent(runtime: runtime)
                    .transition(.fullScreenSurface(scale: 1.02))
            }
        }
        .animation(.smooth(duration: 0.4), value: runtime?.session.isPresented ?? false)
    }
}

/// The overlay's layout, split out so `AssistantOverlayView` stays an empty
/// view when nothing is showing.
private struct AssistantOverlayContent: View {
    let runtime: AssistantRuntime

    var body: some View {
        ZStack {
            Rectangle()
                .fill(.black.opacity(0.6))
                .background(.ultraThinMaterial)
                .ignoresSafeArea()
                .onTapGesture(perform: backgroundTapped)
            edgeGlow
            VStack(spacing: Theme.Spacing.l) {
                topBar
                ListeningLevel(phase: runtime.phase) { AssistantOrb(phase: runtime.phase, level: $0, size: 88) }
                content
                    .frame(maxWidth: 980, maxHeight: .infinity)
                bottomBar
            }
            // The screen padding every surface uses, so the close button sits
            // where it does on every other screen (64 points from the side, 44
            // from the top, with the shell's margin).
            .padding(Theme.Spacing.l)
            .fullScreenSurfaceContent()
        }
        .foregroundStyle(.white)
        // Dark whatever the app's appearance. A preferred color scheme here
        // would set the whole window's.
        .environment(\.colorScheme, .dark)
        .nightModeAware()
        .appAccent(AssistantPalette.accent)
    }

    /// The glow belongs to the request, as on HomeView: it shows while listening
    /// and while working on an answer, and fades once the answer or an error is
    /// up. Gone, its view and its redraws stop, not only its color.
    private var edgeGlow: some View {
        ZStack {
            if showsGlow {
                ListeningLevel(phase: runtime.phase) { EdgeGlow(phase: runtime.phase, level: $0) }
                    .transition(.opacity)
            }
        }
        .animation(Theme.Motion.screen, value: showsGlow)
    }

    private var showsGlow: Bool {
        switch runtime.phase {
        case .listening: true
        case .thinking: runtime.session.answer.isEmpty && runtime.session.errorMessage == nil
        case .idle, .speaking, .error: false
        }
    }

    @ViewBuilder
    private var content: some View {
        if let prompt = runtime.confirmations.pending {
            ConfirmationPromptView(question: prompt.question) { runtime.confirmations.resolve($0) }
        } else if runtime.session.needsSetup {
            EmptyStateView(
                "Add an AI Provider",
                message: runtime.session.errorMessage
                    ?? "HomePad can use Apple Intelligence on this iPad, or a provider you choose, such as ChatGPT, Claude or Gemini.",
                systemImage: "sparkles", actionTitle: "Set Up", action: runtime.openSetup
            )
        } else if runtime.phase == .listening {
            ListeningView(transcript: runtime.session.transcript, previousAnswer: runtime.session.answer)
        } else {
            AnswerView(session: runtime.session, phase: runtime.phase)
        }
    }

    private var topBar: some View {
        HStack {
            if let provider = runtime.session.providerName {
                GlassPill(provider, systemImage: "sparkles")
            }
            Spacer()
            CloseButton("Dismiss") { runtime.dismiss() }
        }
    }

    private var bottomBar: some View {
        HStack(spacing: Theme.Spacing.l) {
            if runtime.phase == .speaking {
                GlassIconButton("stop.fill", label: "Stop Speaking") { runtime.stopSpeaking() }
            }
            if runtime.phase == .listening {
                GlassIconButton("waveform", label: "Done Speaking", size: Theme.Size.roundControl, tint: AssistantPalette.accent) { runtime.stopListening() }
            } else if !runtime.session.needsSetup, runtime.confirmations.pending == nil {
                GlassIconButton("mic.fill", label: "Ask a Follow-Up", size: Theme.Size.roundControl, tint: AssistantPalette.accent) { runtime.startListening() }
            }
        }
        .animation(.smooth, value: runtime.phase)
    }

    /// A tap while talking interrupts the speech. Otherwise it closes the overlay.
    private func backgroundTapped() {
        if runtime.phase == .speaking {
            runtime.stopSpeaking()
        } else if runtime.confirmations.pending == nil {
            runtime.dismiss()
        }
    }
}

/// Hands the microphone level to the orb and the edge glow, and only while
/// listening, the one phase that uses it. Read in the overlay's own body, the
/// level redrew the answer and its cards with every microphone buffer, about
/// twelve times a second in every phase, since the wake phrase keeps the
/// microphone running.
private struct ListeningLevel<Content: View>: View {
    let phase: AssistantPhase
    @ViewBuilder let content: (Double) -> Content
    @Environment(AppServices.self) private var services

    var body: some View {
        content(phase == .listening ? services.microphone.level : 0)
    }
}
