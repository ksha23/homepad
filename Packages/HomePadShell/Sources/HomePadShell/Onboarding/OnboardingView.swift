import HomePadCore
import HomePadUI
import SwiftUI

/// The steps of first-launch setup, in order.
enum OnboardingStep: Int, CaseIterable {
    case welcome, household, people, privacy, face, connect
}

/// First-launch setup, shown once and skippable at every step: welcome,
/// household name, people, sensing and privacy, a face, then shortcuts into
/// the assistant and smart home settings.
struct OnboardingView: View {
    @Environment(ShellCoordinator.self) private var coordinator
    @State private var step: OnboardingStep = .welcome
    @State private var appliedLaunchStep = false
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            // The dusk gradient, dimmed toward the page color: deep in Dark,
            // a soft pastel in Light, so `.primary` text reads on both.
            WallpaperBackground(choice: .dusk, accent: .blue, photo: nil)
                .overlay(Color.screenBackground.opacity(colorScheme == .light ? 0.6 : 0.35))
                .ignoresSafeArea()
            VStack(spacing: Theme.Spacing.l) {
                topBar
                Spacer(minLength: 0)
                stepContent
                    .frame(maxWidth: 680)
                    .id(step)
                    .transition(.asymmetric(insertion: .move(edge: .trailing), removal: .move(edge: .leading)).combined(with: .opacity))
                Spacer(minLength: 0)
                bottomBar
            }
            .padding(Theme.Spacing.l)
            .coverScreenMargin()
        }
        .animation(Theme.Motion.screen, value: step)
        .onAppear {
            guard !appliedLaunchStep else { return }
            appliedLaunchStep = true
            if let start = coordinator.launchOptions.onboardingStep { step = start }
        }
    }

    private var topBar: some View {
        HStack {
            if step != .welcome {
                GlassCapsuleButton("Back", systemImage: "chevron.left", size: .regular) { move(by: -1) }
            }
            Spacer()
            if step != .connect {
                GlassCapsuleButton("Skip Setup", size: .regular) { coordinator.finishOnboarding() }
            }
        }
    }

    @ViewBuilder
    private var stepContent: some View {
        switch step {
        case .welcome: OnboardingWelcomeStep()
        case .household: OnboardingHouseholdStep()
        case .people: OnboardingPeopleStep()
        case .privacy: OnboardingPrivacyStep()
        case .face: OnboardingFaceStep()
        case .connect: OnboardingConnectStep()
        }
    }

    private var bottomBar: some View {
        VStack(spacing: Theme.Spacing.m) {
            Button {
                if step == .connect { coordinator.finishOnboarding() } else { move(by: 1) }
            } label: {
                Text(step == .welcome ? "Get Started" : (step == .connect ? "Done" : "Continue"))
                    .font(.title3.weight(.semibold))
                    .frame(maxWidth: 420, minHeight: 40)
            }
            .buttonStyle(.glassProminent)
            .controlSize(.large)
            // Steps move with the buttons only, so tapping a dot does nothing.
            PageDots(count: OnboardingStep.allCases.count, selection: Binding(get: { step.rawValue }, set: { _ in }))
        }
    }

    private func move(by offset: Int) {
        guard let next = OnboardingStep(rawValue: step.rawValue + offset) else { return }
        // The privacy step explains the camera and microphone. Ask right after it.
        if step == .privacy && offset > 0 { coordinator.requestSensingPermissions() }
        step = next
    }
}

/// Shared layout for a step: a big symbol, a title, a short explanation, then content.
struct OnboardingStepLayout<Content: View>: View {
    let systemImage: String
    let title: String
    let message: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(spacing: Theme.Spacing.l) {
            Image(systemName: systemImage)
                .font(.system(size: 72, weight: .medium))
                .symbolRenderingMode(.hierarchical)
            Text(title)
                .font(.glanceTitle)
                .multilineTextAlignment(.center)
            Text(message)
                .font(.title3)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            content
        }
        .foregroundStyle(.primary)
    }
}
