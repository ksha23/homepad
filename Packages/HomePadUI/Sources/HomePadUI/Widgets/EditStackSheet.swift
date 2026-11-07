import HomePadCore
import SwiftUI

/// Edit Stack, as on iPadOS: a stack's widgets in a list, to drag into
/// another order, remove, or open one's own settings (Edit Widget), with
/// Smart Rotate and the widgets that can join it. Changes apply as they are
/// made, so the sheet has only its close button.
///
///     EditStackSheet(stack: $stack, size: .medium, tile: frame.size, widget: registry.widget,
///                    addable: candidates, isLocked: isLocked) { widget, settings in
///         widget.makeView(.medium).environment(\.widgetSettings, settings)
///     }
///
/// Present it page-sized (`.presentationSizing(.page)`). A stack with one
/// widget left becomes that widget, so the place that holds it closes the
/// sheet once the second to last is removed.
public struct EditStackSheet<Preview: View>: View {
    @Binding private var stack: WidgetStack
    private let size: WidgetSize
    private let tile: CGSize
    private let widget: (String) -> WidgetDescriptor?
    private let addable: [WidgetDescriptor]
    private let isLocked: (WidgetDescriptor) -> Bool
    private let preview: (WidgetDescriptor, WidgetSettings) -> Preview
    /// The widget whose settings are open, by member ID.
    @State private var path: [String] = []
    @Environment(\.dismiss) private var dismiss

    /// - Parameters:
    ///   - stack: The stack where it sits, saved as each change is made.
    ///   - size: Its size where it sits.
    ///   - tile: The size it is drawn at where it sits, for the previews.
    ///   - widget: Looks a member's widget up by its ID. Nil for one whose module is gone.
    ///   - addable: Widgets that can join the stack at its size.
    ///   - isLocked: True for a personal widget nobody may see now: its preview
    ///     and settings stay closed, as on the Home Screen and the faces.
    ///   - preview: Draws a widget at the stack's size with its settings.
    public init(stack: Binding<WidgetStack>, size: WidgetSize, tile: CGSize, widget: @escaping (String) -> WidgetDescriptor?,
                addable: [WidgetDescriptor], isLocked: @escaping (WidgetDescriptor) -> Bool,
                @ViewBuilder preview: @escaping (WidgetDescriptor, WidgetSettings) -> Preview) {
        _stack = stack
        self.size = size
        self.tile = tile
        self.widget = widget
        self.addable = addable
        self.isLocked = isLocked
        self.preview = preview
    }

    /// The room a widget's preview takes in its row: about as tall as a round
    /// control, so a row stays a walk-up target and the list still shows several.
    static var previewBox: CGSize { CGSize(width: Theme.Size.roundControl * 2, height: Theme.Size.roundControl) }

    public var body: some View {
        NavigationStack(path: $path) {
            SheetScreen("Edit Stack", onClose: { dismiss() }) {
                List {
                    Section {
                        Toggle("Smart Rotate", isOn: $stack.smartRotate)
                            .frame(minHeight: Theme.Size.tapTarget)
                    } footer: {
                        Text("Turns to the widget that matters now, such as Timers while one runs, and back once it passes.")
                    }
                    Section {
                        ForEach(stack.members) { member in
                            row(member)
                        }
                        .onMove { stack.move(fromOffsets: $0, toOffset: $1) }
                        .onDelete { offsets in
                            stack.members.remove(atOffsets: offsets)
                        }
                    } header: {
                        Text("Widgets")
                    } footer: {
                        Text("Drag to change the order. The stack rests on the first. A stack with one widget left becomes that widget.")
                    }
                    if !stack.isFull, !joining.isEmpty {
                        Section("Add a Widget") {
                            ForEach(joining) { widget in
                                addRow(widget)
                            }
                        }
                    }
                }
                .alwaysEditing()
            }
            .navigationDestination(for: String.self) { memberID in
                if let member = stack.member(memberID), let widget = widget(member.widgetID) {
                    EditWidgetSheet(widget: widget, size: size, tile: tile, settings: settings(of: memberID),
                                    onBack: { path.removeLast() }, backLabel: "Edit Stack", onClose: { dismiss() })
                }
            }
        }
    }

    /// Widgets that can join: those that come in the stack's size and are not in it yet.
    /// A widget with settings can join again, since each copy keeps its own.
    private var joining: [WidgetDescriptor] {
        let present = Set(stack.members.map(\.widgetID))
        return addable.filter { $0.supportedSizes.contains(size) && ($0.hasSettings || !present.contains($0.id)) }
    }

    @ViewBuilder
    private func row(_ member: WidgetStack.Member) -> some View {
        let widget = widget(member.widgetID)
        let locked = widget.map(isLocked) ?? true
        HStack(spacing: Theme.Spacing.m) {
            Group {
                if let widget, !locked {
                    WidgetPreview(tile: tile, fitting: Self.previewBox) {
                        preview(widget, member.settings ?? WidgetSettings())
                    }
                } else {
                    Image(systemName: locked && widget != nil ? "lock.fill" : (widget?.systemImage ?? "questionmark.square.dashed"))
                        .font(.title2)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: Self.previewBox.width, height: Self.previewBox.height)
            VStack(alignment: .leading, spacing: 2) {
                Text(widget?.title ?? "Unavailable Widget")
                    .font(.tileTitle)
                if widget == nil {
                    Text("Its part of HomePad is not installed.")
                        .font(.tileDetail)
                        .foregroundStyle(.secondary)
                } else if locked {
                    Text("Locked until you are recognized")
                        .font(.tileDetail)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
            if let widget, widget.hasSettings, !locked {
                Button("Edit") { path.append(member.id) }
                    .buttonStyle(.glassCapsule(size: .regular))
                    .accessibilityLabel("Edit \(widget.title)")
            }
        }
        .frame(minHeight: Theme.Size.tapTarget)
        .accessibilityElement(children: .combine)
    }

    private func addRow(_ widget: WidgetDescriptor) -> some View {
        Button {
            withAnimation(Theme.Motion.standard) { stack.append(WidgetStack.Member(widgetID: widget.id)) }
        } label: {
            HStack(spacing: Theme.Spacing.m) {
                Image(systemName: "plus.circle.fill")
                    .font(.title2)
                    .foregroundStyle(.green)
                Label(widget.title, systemImage: widget.systemImage)
                    .font(.tileTitle)
                    .foregroundStyle(.primary)
                Spacer(minLength: 0)
            }
            .frame(minHeight: Theme.Size.tapTarget)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Add \(widget.title)")
    }

    private func settings(of memberID: String) -> Binding<WidgetSettings> {
        Binding(get: { stack.settings(for: memberID) }, set: { stack.setSettings($0, for: memberID) })
    }
}

private extension View {
    /// Always editing, as iPadOS's Edit Stack is: handles to drag and buttons to remove.
    @ViewBuilder
    func alwaysEditing() -> some View {
        #if os(iOS)
        environment(\.editMode, .constant(.active))
        #else
        self
        #endif
    }
}
