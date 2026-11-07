import HomePadCore
import HomePadUI
import SwiftUI

/// The slots page of the face editor: one card per slot showing what is in
/// it, or a dashed "Add" card when it is empty. Tap a slot to pick from the
/// gallery, as on Apple Watch. The gallery's first row empties a slot.
struct SlotsPage: View {
    let slots: [FaceSlot]
    let gallery: SlotGallery
    /// A sentence under the slots, such as what leaving them all empty does.
    var note: String?
    @Binding var face: FaceConfiguration

    @Environment(AppServices.self) private var services
    @State private var choosing: FaceSlot?

    var body: some View {
        GeometryReader { proxy in
            grid(columns: EditorMetrics.slotColumns(count: slots.count, width: proxy.size.width))
        }
        .sheet(item: $choosing) { slot in
            SlotGallerySheet(gallery: gallery, slot: slot, selection: currentValue(slot) ?? "") { picked in
                face.slots[slot.id] = picked
                choosing = nil
            }
        }
    }

    private func grid(columns: Int) -> some View {
        let items = SlotItem.items(for: gallery, services: services)
        return VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: Theme.Spacing.m), count: columns),
                      spacing: Theme.Spacing.m) {
                ForEach(slots) { slot in
                    Button { choosing = slot } label: {
                        SlotCard(slot: slot, item: item(in: slot, from: items), addTitle: gallery.addTitle)
                    }
                    .buttonStyle(.plain)
                }
            }
            if let note {
                Text(note)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    /// What a slot shows: its item, what the face picks by itself when it is
    /// empty, or nothing. An item that is gone (a removed accessory) shows as empty.
    private func item(in slot: FaceSlot, from items: [SlotItem]) -> SlotItem? {
        if let id = currentValue(slot), let item = items.first(where: { $0.id == id }) { return item }
        return slot.automaticTitle.map { SlotItem(id: "", title: $0, systemImage: "wand.and.stars") }
    }

    /// The slot's value as this HomePad knows it, since the face may have been
    /// set up on another HomePad.
    private func currentValue(_ slot: FaceSlot) -> String? {
        if let value = face.slots[slot.id] {
            return value.isEmpty ? nil : SlotItem.localID(value, gallery: gallery, home: services.smartHome)
        }
        if gallery == .cities, slot.id.hasPrefix("city"), let index = Int(slot.id.dropFirst(4)),
           WorldClockFace.defaultCities.indices.contains(index - 1) {
            return WorldClockFace.defaultCities[index - 1]
        }
        return nil
    }
}

/// One slot: the chosen item's symbol and name under the slot's name, or a
/// dashed card that offers to add one.
private struct SlotCard: View {
    let slot: FaceSlot
    let item: SlotItem?
    let addTitle: String

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
        HStack(spacing: Theme.Spacing.m) {
            Image(systemName: item?.systemImage ?? "plus")
                .font(.title2)
                .foregroundStyle(item == nil ? AnyShapeStyle(.secondary) : AnyShapeStyle(.tint))
                .frame(width: Theme.Size.minTapTarget, height: Theme.Size.minTapTarget)
            VStack(alignment: .leading, spacing: 0) {
                Text(heading)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text(item?.title ?? addTitle)
                    .font(.headline)
                    .foregroundStyle(item == nil ? .secondary : .primary)
            }
            .lineLimit(1)
            Spacer(minLength: 0)
        }
        .padding(Theme.Spacing.m)
        .frame(minHeight: EditorMetrics.slotHeight)
        .background(item == nil ? AnyShapeStyle(.clear) : AnyShapeStyle(.ultraThinMaterial), in: shape)
        .overlay {
            if item == nil {
                shape.strokeBorder(.primary.opacity(0.3), style: StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
            } else {
                shape.strokeBorder(.primary.opacity(0.15), lineWidth: 1)
            }
        }
        .contentShape(shape)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(heading), \(item?.title ?? addTitle)")
    }

    /// The slot's name, with the item's second line when it has one
    /// ("Tile 1, Kitchen"), so two accessories with one name differ.
    private var heading: String {
        guard let subtitle = item?.subtitle else { return slot.title }
        return "\(slot.title), \(subtitle)"
    }
}
