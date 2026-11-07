import HomePadCore
import HomePadUI
import SwiftUI

/// One widget on a face, drawn straight into its frame at its size, with its
/// own settings. Widgets draw their own tile, so the face adds only the
/// tile's corners. A personal widget nobody may see yet draws locked instead
/// (`LockedWidgetTile`).
struct FaceWidgetTile: View {
    let widget: WidgetDescriptor
    let size: WidgetSize
    var isLocked = false
    /// The placed widget's settings (`FaceWidgetLayout.settings(for:)`). Empty in the gallery.
    var settings = WidgetSettings()

    var body: some View {
        Group {
            if isLocked {
                LockedWidgetTile(widget: widget, size: size)
            } else {
                widget.makeView(size)
                    .environment(\.widgetSettings, settings)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.tile, style: .continuous))
    }
}

/// A widget stack on a face (HomePadUI's `WidgetStackView`): its widgets
/// that may show, flipped with a vertical swipe on the wall and still in
/// previews and the editor. A personal widget nobody may see yet draws
/// locked in previews and is left out on the wall, as a single one is.
struct FaceStackTile: View {
    /// The placement's ID, the stack's ID in what stacks remember (`WidgetStackMemory`).
    let id: UUID
    let items: [WidgetStackItem]
    let size: WidgetSize
    let smartRotate: Bool
    /// True on the wall. Previews and the editor hold it still.
    var isInteractive = false

    var body: some View {
        WidgetStackView(stackID: id.uuidString, items: items, smartRotate: smartRotate, isInteractive: isInteractive) { item in
            if item.isAvailable {
                item.widget.makeView(size)
                    .environment(\.widgetSettings, item.member.settings ?? WidgetSettings())
            } else {
                LockedWidgetTile(widget: item.widget, size: size)
            }
        }
    }

    /// A stack's widgets as they show here: those installed, each shown,
    /// locked or left out by `FaceWidgetAccess`.
    @MainActor
    static func items(_ stack: WidgetStack, registry: ModuleRegistry, showPersonal: Bool,
                      keepsPersonalPlaces: Bool) -> [WidgetStackItem] {
        stack.members.compactMap { member in
            guard let widget = registry.widget(member.widgetID) else { return nil }
            let access = FaceWidgetAccess.of(widget, showPersonal: showPersonal, keepsPersonalPlaces: keepsPersonalPlaces)
            guard access != .hidden else { return nil }
            return WidgetStackItem(member: member, widget: widget, isAvailable: access == .shown)
        }
    }
}

/// Holds a personal widget's place while nobody is recognized: the widget's
/// name and symbol over gray placeholder lines and a lock. Nothing of the
/// widget's own content is drawn, so no personal data can show.
struct LockedWidgetTile: View {
    let widget: WidgetDescriptor
    let size: WidgetSize

    var body: some View {
        GlassTile {
            Label(widget.title, systemImage: widget.systemImage)
                .font(.tileTitle)
                .lineLimit(1)
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                // Placeholder text, drawn as gray bars like a widget loading.
                Text("Placeholder event at noon")
                Text("Another placeholder line")
                if size != .small { Text("A third placeholder line here") }
            }
            .font(.subheadline)
            .redacted(reason: .placeholder)
            .accessibilityHidden(true)
            Spacer(minLength: 0)
            Label("Locked", systemImage: "lock.fill")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(widget.title), locked until you are recognized")
    }
}

/// Who may see a personal widget on a face.
enum FaceWidgetAccess {
    /// Draws normally.
    case shown
    /// Draws as `LockedWidgetTile`, in previews while nobody is recognized.
    case locked
    /// Left out, on the wall while nobody is recognized. Its cells stay empty.
    case hidden

    /// The rule for one widget: personal widgets show once someone is
    /// recognized. Until then previews (`keepsPersonalPlaces`) lock them, so
    /// the layout is the one a recognized member sees, and the wall leaves them out.
    static func of(_ widget: WidgetDescriptor, showPersonal: Bool, keepsPersonalPlaces: Bool) -> FaceWidgetAccess {
        guard widget.isPersonal, !showPersonal else { return .shown }
        return keepsPersonalPlaces ? .locked : .hidden
    }
}
