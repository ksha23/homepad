import HomePadCore
import HomePadUI
import SwiftUI

/// Tiles that are not in Control Center right now, built-in and from modules.
struct ControlGallerySheet: View {
    let store: ControlCenterStore

    var body: some View {
        let hidden = store.hiddenIDs
        // A tap adds a control at once, so the sheet only closes.
        SheetScreen("Add a Control") {
            List {
                if hidden.isEmpty {
                    Text("Every control is already in Control Center.")
                        .foregroundStyle(.secondary)
                }
                ForEach(hidden, id: \.self) { id in
                    Button {
                        store.update { $0.add(id) }
                    } label: {
                        HStack(spacing: Theme.Spacing.m) {
                            Image(systemName: store.systemImage(for: id))
                                .font(.title3)
                                .frame(width: 40, height: 40)
                                .background(Circle().fill(.primary.opacity(0.12)))
                            Text(store.title(for: id)).font(.body.weight(.medium))
                            Spacer()
                            Image(systemName: "plus.circle.fill")
                                .font(.title2)
                                .foregroundStyle(.green)
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Add \(store.title(for: id))")
                }
            }
        }
    }
}
