import HomePadCore
import HomePadUI
import SwiftUI

/// Room order, which rooms and accessories appear, and tile sizes. Changes
/// apply as they are made. Edit shows the handles that reorder rooms, and
/// Done, the header's prominent action while editing, hides them again.
struct LayoutEditorView: View {
    @Environment(UnifiedSmartHomeService.self) private var service
    @State private var isEditing = false

    private var rooms: [String] {
        service.layout.ordered(Array(Set(service.allAccessories.compactMap(\.room))))
    }

    var body: some View {
        SheetScreen("Rooms and Accessories") {
            GlassCapsuleButton(isEditing ? "Done" : "Edit", isProminent: isEditing) {
                withAnimation(Theme.Motion.standard) { isEditing.toggle() }
            }
        } content: {
            List {
                Section {
                    ForEach(rooms, id: \.self) { room in
                        Toggle(room, isOn: Binding(
                            get: { !service.layout.hiddenRooms.contains(room) },
                            set: { service.layout.setRoom(room, visible: $0) }
                        ))
                    }
                    .onMove { source, destination in
                        var order = rooms
                        order.move(fromOffsets: source, toOffset: destination)
                        service.layout.roomOrder = order
                    }
                } header: {
                    Text("Rooms")
                } footer: {
                    Text("Drag to reorder. Hidden rooms disappear from the Home app, faces and widgets.")
                }
                ForEach(rooms + [""], id: \.self) { room in
                    let items = service.allAccessories.filter { ($0.room ?? "") == room }
                    if !items.isEmpty {
                        Section(room.isEmpty ? "Other" : room) {
                            ForEach(items) { accessoryRow($0) }
                        }
                    }
                }
            }
            .environment(\.editMode, .constant(isEditing ? .active : .inactive))
        }
    }

    private func accessoryRow(_ accessory: HomeAccessory) -> some View {
        HStack {
            Toggle(isOn: Binding(
                get: { service.layout.isVisible(id: accessory.id, room: accessory.room) },
                set: { service.layout.setItem(accessory.id, room: accessory.room, visible: $0) }
            )) {
                Label(accessory.name, systemImage: AccessoryPresentation.symbol(for: accessory))
            }
            Picker("Tile", selection: Binding(
                get: { service.layout.tileSize(for: accessory) },
                set: { service.layout.tileSizes[accessory.id] = $0 }
            )) {
                ForEach(TileSize.allCases, id: \.self) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .controlSize(.large)
            .frame(width: 160)
            .labelsHidden()
        }
    }
}
