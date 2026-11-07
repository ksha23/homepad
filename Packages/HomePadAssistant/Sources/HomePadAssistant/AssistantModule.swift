import HomePadCore
import HomePadUI
import SwiftUI

/// The AI assistant: any provider (Apple on device, OpenAI, Claude, Gemini,
/// Grok, Meta Muse, Mistral, DeepSeek, Groq, Perplexity, OpenRouter, Ollama,
/// LM Studio), tool calling over the registry, voice in and out, the Siri-style
/// overlay, the Assistant app and the AI Assistant settings pane.
public enum AssistantModule: HomePadModule {
    public static let id = "assistant"
    public static let appID = "assistant"
    public static let settingsPaneID = "assistant"

    public static func register(services: AppServices, registry: ModuleRegistry) {
        let runtime = AssistantRuntime(services: services, registry: registry)
        services.assistant = runtime
        registry.register(tools: runtime.makeTools())
        registry.register(overlay: OverlayDescriptor(id: "assistant.overlay", zIndex: 900) { AssistantOverlayView() })
        registry.register(app: AppDescriptor(
            id: appID, title: "Assistant", systemImage: "sparkles", tint: AssistantPalette.accent,
            category: .productivity, sortOrder: 20
        ) { AssistantAppView() })
        registry.register(settings: SettingsPaneDescriptor(
            id: settingsPaneID, title: "AI Assistant", systemImage: "sparkles", tint: AssistantPalette.accent, sortOrder: 30, adminOnly: true
        ) { AssistantSettingsView() })
    }

    public static func didFinishLaunching(services: AppServices, registry: ModuleRegistry) {
        guard let runtime = services.assistant as? AssistantRuntime else { return }
        runtime.start()
    }
}
