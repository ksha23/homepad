import HomePadCore
import HomePadUI
import SwiftUI

/// Picks which provider answers typed requests in the app. It sits next to
/// the app's title.
struct ProviderSwitcher: View {
    let runtime: AssistantRuntime

    var body: some View {
        let ready = runtime.providers.readyProviders
        HeaderPicker(
            "Provider", selection: Binding(get: { runtime.chatProviderOverride }, set: { runtime.chatProviderOverride = $0 }),
            title: label(ready), systemImage: "sparkles"
        ) {
            Text("Automatic").tag(String?.none)
            ForEach(ready) { Label($0.displayName, systemImage: $0.systemImage).tag(Optional($0.id)) }
        }
        .disabled(ready.isEmpty)
    }

    private func label(_ ready: [ProviderDescriptor]) -> String {
        if let id = runtime.chatProviderOverride, let descriptor = ready.first(where: { $0.id == id }) { return descriptor.displayName }
        return ready.isEmpty ? "No Provider" : "Automatic"
    }
}
