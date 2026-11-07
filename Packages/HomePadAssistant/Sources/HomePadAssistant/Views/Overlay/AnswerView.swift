import HomePadCore
import HomePadUI
import SwiftUI

/// The request, the streaming answer in big type, and any cards.
struct AnswerView: View {
    let session: AssistantSession
    let phase: AssistantPhase
    @Environment(\.proximity) private var proximity

    var body: some View {
        ScrollViewReader { reader in
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.l) {
                    request
                    if session.answer.isEmpty, phase == .thinking {
                        ThinkingLine(text: session.activity ?? "Thinking")
                            .transition(.opacity)
                    } else if !session.answer.isEmpty {
                        // The key facts in bold, as on HomeView.
                        let size: CGFloat = proximity >= .mid ? 40 : 52
                        Text(AnswerMarkdown.attributed(session.answer, boldFont: .system(size: size, weight: .bold)))
                            .font(.system(size: size, weight: .medium))
                            .lineSpacing(6)
                            .textSelection(.enabled)
                            .transition(Self.arrival)
                    }
                    if let activity = session.activity, !session.answer.isEmpty {
                        ThinkingLine(text: activity)
                    }
                    if let error = session.errorMessage {
                        Label(error, systemImage: "exclamationmark.triangle.fill")
                            .font(.title2)
                            .foregroundStyle(.yellow)
                            .transition(Self.arrival)
                    }
                    // Sources as small chips under the answer, as on HomeView.
                    let sources = session.cards.filter { $0.kind == .link }
                    if !sources.isEmpty {
                        SourceChipsView(cards: sources)
                            .transition(.opacity)
                    }
                    ForEach(session.cards.filter { $0.kind != .link }) { card in
                        AssistantCardView(card: card)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                    Color.clear.frame(height: 1).id("end")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .animation(.smooth, value: session.cards.count)
                // The answer's first words and any error fade in and settle,
                // once. Later words stream in as they come.
                .animation(Theme.Motion.standard, value: session.answer.isEmpty)
                .animation(Theme.Motion.standard, value: session.errorMessage)
            }
            .scrollIndicators(.hidden)
            .onChange(of: session.cards.count) { reader.scrollTo("end", anchor: .bottom) }
        }
    }

    /// How an answer arrives: it fades in as it rises a little into place.
    private static let arrival: AnyTransition = .opacity.combined(with: .offset(y: 16))

    @ViewBuilder
    private var request: some View {
        if !session.transcript.isEmpty || session.attachedImage != nil {
            HStack(alignment: .top, spacing: Theme.Spacing.m) {
                if let data = session.attachedImage {
                    PhotoThumbnail(data: data, side: 72)
                }
                Text(session.transcript)
                    .font(.title2)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

/// A gently pulsing status line such as "Checking the weather".
struct ThinkingLine: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.title.weight(.medium))
            .foregroundStyle(.secondary)
            .phaseAnimator([0.45, 1.0]) { view, opacity in
                view.opacity(opacity)
            } animation: { _ in .easeInOut(duration: 0.9) }
    }
}
