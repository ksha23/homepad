import HomePadUI
import SwiftUI

/// One question and its answer.
struct ChatTurnView: View {
    let userText: String
    let answer: String
    let provider: String
    var hadImage = false
    var activity: String?

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            HStack {
                Spacer(minLength: 120)
                HStack(spacing: Theme.Spacing.s) {
                    if hadImage { Image(systemName: "photo") }
                    Text(userText)
                }
                .font(.title3)
                .padding(.horizontal, Theme.Spacing.l)
                .padding(.vertical, Theme.Spacing.m)
                .glassEffect(.regular.tint(AssistantPalette.accent.opacity(0.5)), in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
            }
            if let activity {
                ThinkingLine(text: activity)
                    .transition(.opacity)
            } else {
                VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                    Text(AnswerMarkdown.attributed(answer, boldFont: .title2.bold())).font(.title2).textSelection(.enabled)
                    if !provider.isEmpty {
                        Text(provider).font(.subheadline).foregroundStyle(.tertiary)
                    }
                }
                // The answer fades in and rises a little into place, once.
                .transition(.opacity.combined(with: .offset(y: 12)))
            }
        }
        .animation(Theme.Motion.standard, value: activity == nil)
    }
}
