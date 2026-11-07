import HomePadCore
import HomePadUI
import SwiftUI

/// The Assistant app: chat history, typing with the onscreen keyboard,
/// attaching a photo, switching providers, and AI settings for admins.
///
/// It reopens on each person's tab, the chat opening at its latest answer.
/// The Settings tab comes back only for someone who may change the settings.
struct AssistantAppView: View {
    @Environment(AppServices.self) private var services
    @AppState(AssistantAppState.tab) private var tab

    var body: some View {
        if let runtime = services.assistant as? AssistantRuntime {
            AppScreen("Assistant", accessory: { accessory }, titleAccessory: {
                if tab == .chat { ProviderSwitcher(runtime: runtime) }
            }) {
                switch tab {
                case .chat: ChatView(runtime: runtime) { tab = .settings }
                case .settings: settings
                }
            }
            .onAppear {
                tab = AssistantAppState.restoredTab(tab, canChangeSettings: canChangeSettings)
                applyRequestedTab(runtime)
            }
            .onChange(of: runtime.requestedAppTab) { applyRequestedTab(runtime) }
        } else {
            EmptyStateView("Assistant Unavailable", message: "The assistant module is not loaded.", systemImage: "sparkles")
        }
    }

    @ViewBuilder
    private var accessory: some View {
        if tab == .chat {
            GlassIconButton("gearshape", label: "Settings") { tab = .settings }
        } else {
            GlassIconButton("bubble.left.and.text.bubble.right", label: "Chat") { tab = .chat }
        }
    }

    /// Settings hold API keys, so only admins (or a household with no members yet) may change them.
    @ViewBuilder
    private var settings: some View {
        if canChangeSettings {
            AssistantSettingsView()
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.tile, style: .continuous))
        } else {
            EmptyStateView(
                "Admins Only",
                message: "A recognized household admin can change AI settings here or in Settings, AI Assistant.",
                systemImage: "lock.fill"
            )
        }
    }

    private var canChangeSettings: Bool {
        let household = services.household
        return household.members.isEmpty || (household.activeMember?.isAdmin == true && household.isPersonalContentUnlocked)
    }

    private func applyRequestedTab(_ runtime: AssistantRuntime) {
        if let requested = runtime.requestedAppTab ?? AssistantDemo.requestedTab {
            tab = requested
            runtime.requestedAppTab = nil
        }
    }
}
