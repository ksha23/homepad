import HomePadCore
import HomePadUI
import SwiftUI

/// Pick and order favorite accessories and scenes, as in a grouped Settings list.
struct FavoritesEditorView: View {
    @Environment(UnifiedSmartHomeService.self) private var service

    var body: some View {
        // Changes apply as they are made, so the sheet only closes.
        SheetScreen("Favorites") {
            List {
                Section("Favorites") {
                    ForEach(service.favorites) { accessory in
                        Label(accessory.name, systemImage: AccessoryPresentation.symbol(for: accessory))
                    }
                    .onMove(perform: service.moveFavorites)
                    .onDelete { offsets in
                        offsets.map { service.favorites[$0].id }.forEach { service.setFavorite($0, isFavorite: false) }
                    }
                }
                Section("Scenes") {
                    ForEach(service.scenes) { scene in
                        star(scene.name, symbol: scene.systemImage, isOn: service.favoriteSceneIDs.contains(scene.id)) {
                            service.setFavoriteScene(scene.id, isFavorite: $0)
                        }
                    }
                }
                let accessories = service.accessories.hidingGroupMembers
                // Rooms with only cameras have nothing to favorite here.
                ForEach(service.orderedRooms.filter { room in accessories.contains { $0.room == room } }, id: \.self) { room in
                    Section(room) {
                        ForEach(accessories.filter { $0.room == room }) { accessory in
                            star(accessory.name, symbol: AccessoryPresentation.symbol(for: accessory),
                                 isOn: service.favoriteAccessoryIDs.contains(accessory.id)) {
                                service.setFavorite(accessory.id, isFavorite: $0)
                            }
                        }
                    }
                }
            }
            .environment(\.editMode, .constant(.active))
        }
    }

    private func star(_ title: String, symbol: String, isOn: Bool, set: @escaping (Bool) -> Void) -> some View {
        Button {
            set(!isOn)
        } label: {
            HStack {
                Label(title, systemImage: symbol).foregroundStyle(.primary)
                Spacer()
                Image(systemName: isOn ? "star.fill" : "star").foregroundStyle(isOn ? .yellow : .secondary)
            }
        }
    }
}
