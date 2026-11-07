import HomePadCore
import HomePadUI
import SwiftUI

/// The gallery for one slot: every widget, city, accessory, scene or camera,
/// grouped the way the Home app groups them, plus a first row that empties the
/// slot ("None", or what the face picks by itself, such as "Automatic").
struct SlotGallerySheet: View {
    let gallery: SlotGallery
    let slot: FaceSlot
    let selection: String
    let onPick: (String) -> Void

    @Environment(AppServices.self) private var services
    @State private var search = ""

    var body: some View {
        SheetScreen(slot.title) {
            VStack(spacing: Theme.Spacing.s) {
                GlassSearchField("Search", text: $search)
                    .padding(.horizontal, Theme.Spacing.l)
                list
            }
        }
    }

    /// A row empties the slot, then the items in their sections. Tapping one picks it.
    private var list: some View {
        List {
            Section {
                row(SlotItem(id: "", title: slot.automaticTitle ?? "None",
                             systemImage: slot.automaticTitle == nil ? "circle.slash" : "wand.and.stars"))
            }
            ForEach(sections, id: \.title) { section in
                Section {
                    ForEach(section.items) { item in row(item) }
                } header: {
                    if !section.title.isEmpty { Text(section.title) }
                }
            }
        }
        .overlay {
            if sections.isEmpty, !search.isEmpty { ContentUnavailableView.search(text: search) }
        }
    }

    /// The items matching the search, in their sections.
    private var sections: [SlotItem.Section] {
        SlotItem.sections(SlotItem.items(for: gallery, services: services), matching: search)
    }

    private func row(_ item: SlotItem) -> some View {
        Button { onPick(item.id) } label: {
            HStack(spacing: Theme.Spacing.m) {
                Image(systemName: item.systemImage)
                    .foregroundStyle(.tint)
                    .frame(minWidth: Theme.Spacing.l)
                VStack(alignment: .leading) {
                    Text(item.title)
                    if let subtitle = item.subtitle {
                        Text(subtitle).font(.footnote).foregroundStyle(.secondary)
                    }
                }
                Spacer()
                if item.id == selection { Image(systemName: "checkmark").foregroundStyle(.tint) }
            }
        }
        .foregroundStyle(.primary)
        .accessibilityAddTraits(item.id == selection ? .isSelected : [])
    }
}
