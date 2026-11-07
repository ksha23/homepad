import HomePadUI
import SwiftUI

/// Asks before a sensitive action. Answer by tapping, saying yes or no, or
/// nodding or shaking your head with AirPods.
struct ConfirmationPromptView: View {
    let question: String
    let answer: (Bool) -> Void

    var body: some View {
        VStack(spacing: Theme.Spacing.xl) {
            Spacer(minLength: 0)
            Image(systemName: "lock.shield.fill")
                .font(.system(size: 64))
                .foregroundStyle(.orange)
            Text(question)
                .font(.system(size: 56, weight: .semibold))
                .multilineTextAlignment(.center)
            Text("Say yes or no, tap below, or nod or shake your head with AirPods.")
                .font(.title3)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            HStack(spacing: Theme.Spacing.l) {
                GlassCapsuleButton("No", systemImage: "xmark", size: .extraLarge) { answer(false) }
                GlassCapsuleButton("Yes", systemImage: "checkmark", size: .extraLarge, isProminent: true, tint: .orange) { answer(true) }
            }
            Spacer(minLength: 0)
        }
    }
}
