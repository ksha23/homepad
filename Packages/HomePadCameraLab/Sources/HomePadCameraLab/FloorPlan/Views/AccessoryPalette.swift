import HomePadCore
import HomePadUI
import SwiftUI

/// Accessories not yet on the plan, grouped by room. Drag one onto the plan.
struct AccessoryPalette: View {
    @Environment(AppServices.self) private var services
    @Environment(\.colorScheme) private var colorScheme
    let plan: FloorPlan

    var body: some View {
        GlassPanel(padding: Theme.Spacing.l) { list }
    }

    private var list: some View {
        let placed = Set(plan.placements.map(\.accessoryID))
        let unplaced = services.smartHome.accessories.filter { !placed.contains($0.id) }
        return VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            SectionHeader("Drag onto the Plan", systemImage: "hand.draw")
            if unplaced.isEmpty {
                Text("Every accessory is on the plan. Long press a pin to remove it.")
                    .foregroundStyle(.secondary)
            }
            ScrollView {
                LazyVStack(alignment: .leading, spacing: Theme.Spacing.s) {
                    ForEach(unplaced) { accessory in
                        HStack(spacing: Theme.Spacing.m) {
                            Image(systemName: accessory.kind.systemImage)
                                .frame(width: 40, height: 40)
                                .background(Theme.tint(for: accessory.kind).opacity(0.25), in: Circle())
                            VStack(alignment: .leading) {
                                Text(accessory.name).font(.tileTitle)
                                Text(accessory.room ?? accessory.backend.displayName).font(.tileDetail).foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 0)
                            Image(systemName: "line.3.horizontal").foregroundStyle(.tertiary)
                        }
                        .padding(Theme.Spacing.s)
                        .background(.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
                        .draggable(accessory.id) {
                            // The preview is drawn without the app's environment, which
                            // crashed a Shell preview that read an environment object.
                            // AccessoryPin takes only plain values. Handing it the
                            // palette's scheme keeps its text and material as they
                            // look on the plan, in Light and Dark.
                            AccessoryPin(accessory: accessory)
                                .environment(\.colorScheme, colorScheme)
                        }
                    }
                }
            }
            .scrollIndicators(.hidden)
        }
    }
}
