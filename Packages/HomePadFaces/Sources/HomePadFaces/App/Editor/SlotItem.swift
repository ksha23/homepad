import HomePadCore
import SwiftUI

/// Something that can fill a slot: a widget, a city, an accessory, a scene or
/// a camera. Its `id` is what the saved face stores for the slot.
struct SlotItem: Identifiable, Hashable {
    let id: String
    let title: String
    /// A second line, such as an accessory's room, so two "Lamp"s differ.
    var subtitle: String?
    let systemImage: String
    /// The group the gallery lists it under, such as a room. Empty for none.
    var section = ""

    /// A titled group of items in the gallery.
    struct Section: Equatable {
        let title: String
        let items: [SlotItem]
    }

    @MainActor
    static func items(for gallery: SlotGallery, services: AppServices) -> [SlotItem] {
        switch gallery {
        case .cities:
            WorldCity.all.map { SlotItem(id: $0.id, title: $0.name, systemImage: "building.2") }
        case .accessoriesAndScenes:
            homeItems(accessories: services.smartHome.accessories, scenes: services.smartHome.scenes)
        case .cameras:
            services.smartHome.cameras.map(item(for:))
        }
    }

    @MainActor
    static func item(for id: String?, gallery: SlotGallery, services: AppServices) -> SlotItem? {
        guard let id else { return nil }
        let local = localID(id, gallery: gallery, home: services.smartHome)
        return items(for: gallery, services: services).first { $0.id == local }
    }

    /// A saved slot value as this HomePad knows it. A face set up on another
    /// HomePad names that HomePad's HomeKit IDs (`SmartHomeService.localID(for:)`).
    @MainActor
    static func localID(_ id: String, gallery: SlotGallery, home: any SmartHomeService) -> String {
        switch gallery {
        case .cities: id
        case .accessoriesAndScenes: HomeTile.localID(id, in: home)
        case .cameras: home.localID(for: id)
        }
    }

    /// Accessories by room, rooms in order and "Other" last, then scenes. Group
    /// members are left out, since the group stands in for them, and so are
    /// cameras, which have their own slots. IDs match `HomeTile.id`.
    static func homeItems(accessories: [HomeAccessory], scenes: [HomeScene]) -> [SlotItem] {
        let shown = accessories.filter { $0.groupID == nil && $0.kind != .camera && $0.kind != .doorbell }
        let rooms = Set(shown.compactMap(\.room)).sorted { $0.localizedStandardCompare($1) == .orderedAscending }
        var items: [SlotItem] = []
        for room in rooms + [nil] {
            let inRoom = shown.filter { $0.room == room }
                .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
            items += inRoom.map { accessory in
                SlotItem(id: HomeTile.accessory(accessory).id, title: accessory.name, subtitle: room,
                         systemImage: accessory.kind.systemImage, section: room ?? "Other")
            }
        }
        items += scenes.map {
            SlotItem(id: HomeTile.scene($0).id, title: $0.name, subtitle: "Scene", systemImage: $0.systemImage, section: "Scenes")
        }
        return items
    }

    static func item(for camera: HomeCamera) -> SlotItem {
        SlotItem(id: camera.id, title: camera.name, subtitle: camera.room,
                 systemImage: camera.isDoorbell ? "video.doorbell.fill" : "video.fill")
    }

    /// Items grouped by section in the order they come, keeping only those
    /// whose title or subtitle contains `search`.
    static func sections(_ items: [SlotItem], matching search: String) -> [Section] {
        let matching = search.isEmpty ? items : items.filter {
            $0.title.localizedCaseInsensitiveContains(search) || ($0.subtitle?.localizedCaseInsensitiveContains(search) ?? false)
        }
        var order: [String] = []
        var groups: [String: [SlotItem]] = [:]
        for item in matching {
            if groups[item.section] == nil { order.append(item.section) }
            groups[item.section, default: []].append(item)
        }
        return order.map { Section(title: $0, items: groups[$0] ?? []) }
    }
}
