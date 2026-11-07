import HomePadCore
import HomePadUI
import SwiftUI

/// Step 1: what HomePad is.
struct OnboardingWelcomeStep: View {
    var body: some View {
        OnboardingStepLayout(
            systemImage: "house.fill",
            title: "Welcome to HomePad",
            message: "This iPad becomes an always-on home display. A beautiful face from across the room, your home and music up close, and an assistant anyone in the family can talk to."
        ) {
            EmptyView()
        }
    }
}

/// Step 2: the household's name.
struct OnboardingHouseholdStep: View {
    @Environment(SettingsStore.self) private var settings

    var body: some View {
        OnboardingStepLayout(
            systemImage: "signpost.right.and.left.fill",
            title: "Name Your Home",
            message: "Other HomePads and your iPhone use this name to find each other."
        ) {
            TextField("Home", text: settings.binding(CoreSettings.householdName))
                .font(.title2.weight(.semibold))
                .multilineTextAlignment(.center)
                .padding(Theme.Spacing.m)
                .glassEffect(.regular, in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
                .frame(maxWidth: 420)
                .submitLabel(.done)
        }
    }
}

/// Step 4: sensing and privacy.
struct OnboardingPrivacyStep: View {
    var body: some View {
        OnboardingStepLayout(
            systemImage: "hand.raised.fill",
            title: "Sensing Stays on This iPad",
            message: "HomePad uses the cameras and microphone to be helpful, and everything is processed right here."
        ) {
            VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                row("figure.walk.arrival", "Presence",
                    "The front camera notices when someone walks up, so the screen wakes and shows more detail. Video is never stored or sent.")
                row("faceid", "Recognition",
                    "Recognizing faces unlocks each person's own apps. Face data never leaves this iPad.")
                row("waveform", "Listening",
                    "The microphone listens for the wake phrase and for alarms such as smoke detectors, on device.")
                row("switch.2", "You're in control",
                    "Turn the camera or microphone off any time in Control Center. Swipe down from the top-right corner.")
            }
            .padding(Theme.Spacing.l)
            .glassEffect(.regular, in: RoundedRectangle(cornerRadius: Theme.Radius.tile, style: .continuous))
        }
    }

    private func row(_ systemImage: String, _ title: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: Theme.Spacing.m) {
            Image(systemName: systemImage)
                .font(.title2)
                .frame(width: 36)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(text).font(.callout).foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }
}
