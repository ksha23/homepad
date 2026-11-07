import HomePadCore
import HomePadUI
import SwiftUI

/// Home Favorites' Edit Widget page: the accessories this widget shows, in
/// order, to drag and take off, then every accessory by room with a check to
/// add or remove it. Search finds one by name, room or kind. Until something
/// is picked the widget shows the Home app's favorites.
struct FavoritesWidgetSettingsView: View {
    @Environment(UnifiedSmartHomeService.self) private var service
    @Binding var settings: WidgetSettings
    @State private var search = ""

    /// Homes with more accessories than this get a search field.
    static let searchFrom = 8

    /// The widget's own accessories, picked on any HomePad, as this one knows them.
    private var chosen: [HomeAccessory.ID]? {
        settings[FavoritesWidgetChoice.accessories].map { service.localIDs(for: $0) }
    }

    private var shown: [HomeAccessory] {
        FavoritesWidgetChoice.shown(chosen, favorites: service.favorites, accessories: service.accessories)
    }

    var body: some View {
        // A group stands in for its members, as on the Home app's tiles.
        let all = service.accessories.hidingGroupMembers
        let shownIDs = shown.map(\.id)
        VStack(spacing: Theme.Spacing.s) {
            if all.count > Self.searchFrom {
                GlassSearchField("Search Accessories", text: $search)
                    .padding(.horizontal, Theme.Spacing.l)
            }
            List {
                if search.isEmpty {
                    inThisWidget(shownIDs)
                    ForEach(rooms(all), id: \.title) { room in
                        Section(room.title) {
                            ForEach(room.accessories) { check($0, shownIDs: shownIDs, showsRoom: false) }
                        }
                    }
                } else {
                    let results = all.filter(isMatch)
                    if results.isEmpty {
                        ContentUnavailableView.search(text: search)
                            .listRowBackground(Color.clear)
                    } else {
                        Section("Results") {
                            ForEach(results) { check($0, shownIDs: shownIDs, showsRoom: true) }
                        }
                    }
                }
            }
            // Rows in the first section drag to reorder and swipe to take off.
            .environment(\.editMode, .constant(.active))
        }
    }

    /// What the widget shows now, in its order.
    @ViewBuilder
    private func inThisWidget(_ shownIDs: [HomeAccessory.ID]) -> some View {
        Section {
            ForEach(shown) { accessory in
                Label {
                    Text(accessory.name)
                } icon: {
                    Image(systemName: AccessoryPresentation.symbol(for: accessory))
                        .foregroundStyle(Theme.tint(for: accessory.kind))
                }
            }
            .onMove { set(FavoritesWidgetChoice.moving(shownIDs, from: $0, to: $1)) }
            .onDelete { set(FavoritesWidgetChoice.removing(shownIDs, at: $0)) }
        } header: {
            Text("In This Widget")
        } footer: {
            Text(chosen == nil
                 ? "Shows your Home favorites. Check accessories below to choose this widget's own."
                 : "This widget shows its own accessories. Your Home favorites stay as they are.")
        }
        if chosen != nil {
            Section {
                Button("Show Home Favorites Instead") { set(nil) }
            }
        }
    }

    /// An accessory with a check that adds it to the widget or takes it off.
    private func check(_ accessory: HomeAccessory, shownIDs: [HomeAccessory.ID], showsRoom: Bool) -> some View {
        let isShown = shownIDs.contains(accessory.id)
        return Button {
            set(FavoritesWidgetChoice.toggling(accessory.id, shown: shownIDs))
        } label: {
            HStack(spacing: Theme.Spacing.m) {
                Image(systemName: AccessoryPresentation.symbol(for: accessory))
                    .foregroundStyle(Theme.tint(for: accessory.kind))
                    .frame(width: 28)
                // Color.primary and Color.secondary, since .primary and .secondary
                // in a button are shades of the tint.
                VStack(alignment: .leading, spacing: 2) {
                    Text(accessory.name).foregroundStyle(Color.primary)
                    if showsRoom, let room = accessory.room {
                        Text(room).font(.subheadline).foregroundStyle(Color.secondary)
                    }
                }
                Spacer()
                Image(systemName: isShown ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isShown ? AnyShapeStyle(.tint) : AnyShapeStyle(Color.secondary))
            }
        }
        .accessibilityLabel(accessory.name)
        .accessibilityValue(isShown ? "In this widget" : "Not in this widget")
        .accessibilityAddTraits(isShown ? .isSelected : [])
    }

    /// The rooms in the person's order with what is in each, then accessories in no room.
    private func rooms(_ all: [HomeAccessory]) -> [(title: String, accessories: [HomeAccessory])] {
        let rooms = service.orderedRooms.compactMap { room -> (title: String, accessories: [HomeAccessory])? in
            let inRoom = all.filter { $0.room == room }
            return inRoom.isEmpty ? nil : (room, inRoom)
        }
        let roomless = all.filter { $0.room == nil }
        return roomless.isEmpty ? rooms : rooms + [("Other", roomless)]
    }

    /// True when the search names the accessory, its room or its kind ("lights").
    private func isMatch(_ accessory: HomeAccessory) -> Bool {
        let kind = AccessoryPresentation.memberCount(2, kind: accessory.kind)
        return [accessory.name, accessory.room ?? "", kind].contains { $0.localizedCaseInsensitiveContains(search) }
    }

    private func set(_ ids: [HomeAccessory.ID]?) {
        withAnimation(Theme.Motion.standard) { settings[FavoritesWidgetChoice.accessories] = ids }
    }
}
