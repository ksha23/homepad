import HomePadCore
import HomePadUI
import SwiftUI

/// The live transcript in very large type while the person speaks.
struct ListeningView: View {
    let transcript: String
    /// Shown above the transcript during a follow-up, whole and for as long as the
    /// person answers it. Cut to three lines and hidden at the first word, a
    /// question like "What kind of music…" could not be read before replying.
    var previousAnswer = ""
    @Environment(\.proximity) private var proximity

    var body: some View {
        VStack(spacing: Theme.Spacing.l) {
            if !previousAnswer.isEmpty {
                Text(AnswerMarkdown.attributed(previousAnswer, boldFont: .title.bold()))
                    .font(.title)
                    .foregroundStyle(.white.opacity(0.75))
                    .lineLimit(8)
                    .minimumScaleFactor(0.6)
                    .multilineTextAlignment(.center)
            }
            Spacer(minLength: 0)
            Text(transcript.isEmpty ? "Go ahead, I'm listening." : transcript)
                .font(.system(size: proximity >= .mid ? 52 : 68, weight: .semibold))
                .foregroundStyle(transcript.isEmpty ? AnyShapeStyle(.secondary) : AnyShapeStyle(.white))
                .multilineTextAlignment(.center)
                .contentTransition(.interpolate)
                .animation(.smooth(duration: 0.2), value: transcript)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity)
    }
}
