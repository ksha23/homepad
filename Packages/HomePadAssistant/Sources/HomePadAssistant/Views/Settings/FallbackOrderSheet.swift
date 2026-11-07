import HomePadCore
import HomePadUI
import SwiftUI

/// Drag ready providers into the order HomePad should try them when one fails.
/// Save keeps the new order, and the close button leaves it as it was.
struct FallbackOrderSheet: View {
    let readyProviders: [ProviderDescriptor]
    @Environment(AppServices.self) private var services
    @Environment(\.dismiss) private var dismiss
    @State private var order: [ProviderDescriptor] = []

    var body: some View {
        SheetScreen("Fallback Order") {
            GlassCapsuleButton("Save", isProminent: true) {
                services.settings[AssistantSettings.fallbackOrder] = order.map(\.id)
                dismiss()
            }
        } content: {
            List {
                Section {
                    ForEach(order) { descriptor in
                        ProviderRow(descriptor: descriptor, status: .ready, showsChevron: false)
                    }
                    .onMove { order.move(fromOffsets: $0, toOffset: $1) }
                } footer: {
                    Text("Drag to reorder. Only providers that are on and set up are listed.")
                }
            }
            .environment(\.editMode, .constant(.active))
        }
        .onAppear {
            let saved = services.settings[AssistantSettings.fallbackOrder]
            order = readyProviders.sorted { (saved.firstIndex(of: $0.id) ?? Int.max) < (saved.firstIndex(of: $1.id) ?? Int.max) }
        }
    }
}
