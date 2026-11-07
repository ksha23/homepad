import HomePadCore
import HomePadUI
import SwiftUI

/// Step 5: pick the face for the always-on screen, from live thumbnails.
struct OnboardingFaceStep: View {
    @Environment(ModuleRegistry.self) private var registry
    @Environment(SettingsStore.self) private var settings

    private let thumbnail = CGSize(width: 200, height: 150)

    var body: some View {
        let selected = FaceResolver.resolve(
            override: nil, memberPreference: nil, defaultID: settings[CoreSettings.defaultFaceID],
            available: registry.faces.map(\.id)
        )
        OnboardingStepLayout(
            systemImage: "clock.fill",
            title: "Choose a Face",
            message: "The face is what HomePad shows when nobody is using it. Everyone can pick their own later."
        ) {
            ViewThatFits(in: .horizontal) {
                faceRow(selected: selected)
                ScrollView(.horizontal) {
                    faceRow(selected: selected)
                }
                .scrollIndicators(.hidden)
            }
        }
    }

    private func faceRow(selected: String?) -> some View {
        HStack(spacing: Theme.Spacing.l) {
            ForEach(registry.faces) { face in
                Button {
                    settings[CoreSettings.defaultFaceID] = face.id
                } label: {
                    VStack(spacing: Theme.Spacing.s) {
                        face.makeView()
                            .environment(\.isThumbnail, true)
                            .allowsHitTesting(false)
                            .frame(width: thumbnail.width * 5, height: thumbnail.height * 5)
                            .scaleEffect(0.2)
                            .frame(width: thumbnail.width, height: thumbnail.height)
                            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
                            .overlay {
                                RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                                    .strokeBorder(face.id == selected ? Color.primary : .primary.opacity(0.2),
                                                  lineWidth: face.id == selected ? 4 : 1)
                            }
                        Text(face.title).font(.headline)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(face.id == selected ? .isSelected : [])
            }
        }
        .padding(Theme.Spacing.s)
    }
}

/// Step 6: shortcuts into the assistant and smart home settings, then done.
struct OnboardingConnectStep: View {
    @Environment(ModuleRegistry.self) private var registry
    @Environment(ShellCoordinator.self) private var coordinator
    @Environment(ShellNavigator.self) private var navigator

    /// Pane IDs registered by the Assistant and Smart Home modules.
    static let assistantPaneID = "assistant"
    static let smartHomePaneID = "smarthome"

    var body: some View {
        OnboardingStepLayout(
            systemImage: "link",
            title: "Connect Your Assistant and Home",
            message: "Pick any AI provider for the assistant, and connect Apple Home or Home Assistant. You can do this any time in Settings."
        ) {
            VStack(spacing: Theme.Spacing.m) {
                shortcut("Choose an AI Assistant", systemImage: "sparkles", paneID: Self.assistantPaneID)
                shortcut("Connect Your Smart Home", systemImage: "homekit", paneID: Self.smartHomePaneID)
            }
            .frame(maxWidth: 480)
        }
    }

    private func shortcut(_ title: String, systemImage: String, paneID: String) -> some View {
        let isAvailable = registry.settingsPanes.contains { $0.id == paneID }
        return Button {
            coordinator.finishOnboarding()
            navigator.openSettings(pane: paneID)
        } label: {
            HStack {
                Label(title, systemImage: systemImage).font(.title3.weight(.semibold))
                Spacer()
                Text(isAvailable ? "Set Up" : "Coming Soon").foregroundStyle(.secondary)
                Image(systemName: "chevron.right").foregroundStyle(.secondary)
            }
            .padding(Theme.Spacing.m)
            .frame(minHeight: Theme.Size.tapTarget)
        }
        .buttonStyle(.glass)
        .disabled(!isAvailable)
    }
}
