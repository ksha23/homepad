import HomePadCore
import HomePadUI
import SwiftUI

/// The widgets page of the face editor, drawn over its preview: the face's
/// widgets at the preview's scale, to drag, resize and remove like widgets in
/// iPadOS jiggle mode. The face under it is drawn without its own widget
/// layer (`\.facesHidesWidgetLayer`), so each widget shows once.
///
/// While a widget moves or resizes, the open cells show faintly and the place
/// it would land is outlined. Cells the face's own content needs show
/// nothing, so it is plain there is no room over the clock. Every change is
/// saved to `face` as it lands (`FaceConfiguration.saveWidgets`).
struct WidgetEditCanvas: View {
    /// The coordinate space gestures report in.
    static let space = "widgetEditCanvas"

    let definition: FaceDefinition
    @Binding var face: FaceConfiguration
    /// The size the face is laid out at before scaling, and its face insets.
    let canvas: CGSize
    let insets: EdgeInsets
    let session: WidgetEditSession

    @Environment(ModuleRegistry.self) private var registry
    @Environment(AppServices.self) private var services
    @Environment(\.displayCondition) private var condition

    var body: some View {
        GeometryReader { proxy in
            let scale = proxy.size.width / max(canvas.width, 1)
            let saved = savedBoard
            let board = session.board(saved: saved)
            ZStack(alignment: .topLeading) {
                // Tapping the face away from the widgets puts the resize handle away.
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture { withAnimation(Theme.Motion.standard) { session.selection = nil } }
                if session.isActive {
                    WidgetCellGuides(grid: board.grid, scale: scale, landing: landing(on: board))
                        .transition(.opacity)
                }
                ForEach(board.items) { item in
                    tile(item, saved: saved, scale: scale)
                }
            }
            .coordinateSpace(.named(Self.space))
            .animation(Theme.Motion.standard, value: session.isActive)
        }
    }

    /// The face's widgets as saved, on its grid.
    var savedBoard: FaceWidgetBoard {
        FaceWidgetBoard.face(definition, configuration: face, size: canvas, insets: insets, registry: registry)
    }

    /// Where the widget being moved or resized lands now, in the face's coordinates.
    private func landing(on board: FaceWidgetBoard) -> CGRect? {
        guard let id = session.lift?.id ?? session.resizingID, let item = board.item(id) else { return nil }
        return board.grid.frame(for: item.area)
    }

    @ViewBuilder
    private func tile(_ item: FaceGridItem, saved: FaceWidgetBoard, scale: CGFloat) -> some View {
        if let widget = registry.widget(item.widgetID) {
            let lift = session.lift?.id == item.id ? session.lift : nil
            let frame = lift.map { $0.frame.offsetBy(dx: session.translation.width, dy: session.translation.height) }
                ?? saved.grid.frame(for: item.area)
            let stack = face.widgetStack(for: item.id, legacySize: definition.widgets.legacySize)
            let sizes = sizes(of: item, widget: widget)
            EditableWidgetTile(
                widget: widget, size: item.size, tile: frame.size, scale: scale,
                isLocked: isLocked(widget), isSelected: session.selection == item.id, isLifted: lift != nil && session.isLifted,
                isNight: FaceDebugOptions.forcesNight || condition == .night || definition.widgets.isAlwaysNight,
                settings: face.widgetSettings(for: item.id, legacySize: definition.widgets.legacySize),
                stack: stack.map { (id: item.id, items: stackItems($0), smartRotate: $0.smartRotate) },
                sizes: sizes,
                actions: actions(for: item, sizes: sizes, saved: saved, scale: scale)
            )
            .offset(x: frame.minX * scale, y: frame.minY * scale)
            .zIndex(lift != nil ? 1 : 0)
            .accessibilityElement(children: .contain)
            .accessibilityLabel(stack == nil ? "\(widget.title), \(item.size.title)" : "Stack, \(item.size.title)")
            .accessibilityActions { accessibilityActions(for: item, sizes: sizes, saved: saved) }
        }
    }

    /// The sizes a widget's handle snaps between: its own, or for a stack those all its widgets come in.
    private func sizes(of item: FaceGridItem, widget: WidgetDescriptor) -> [WidgetSize] {
        guard let stack = face.widgetStack(for: item.id, legacySize: definition.widgets.legacySize) else {
            return widget.supportedSizes
        }
        return FaceWidgetBoard.stackSizes(stack, registry: registry)
    }

    /// A stack's widgets as the editor shows them: personal ones locked until someone is recognized.
    private func stackItems(_ stack: WidgetStack) -> [WidgetStackItem] {
        let showPersonal = services.household.isPersonalContentUnlocked || FaceDebugOptions.forcesPersonal
        return FaceStackTile.items(stack, registry: registry, showPersonal: showPersonal, keepsPersonalPlaces: true)
    }

    private func actions(for item: FaceGridItem, sizes: [WidgetSize], saved: FaceWidgetBoard,
                         scale: CGFloat) -> EditableWidgetTile.Actions {
        EditableWidgetTile.Actions(
            select: { withAnimation(Theme.Motion.standard) { session.selection = item.id } },
            remove: { remove(item.id, from: saved) },
            drag: { translation in
                if session.lift == nil {
                    session.beginDrag(item.id, on: saved)
                    FacesPerfTrace.begin("editor.widgetDrag")
                }
                session.drag(by: CGSize(width: translation.width / scale, height: translation.height / scale))
            },
            drop: {
                FacesPerfTrace.end("editor.widgetDrag")
                if let board = session.drop() { save(board) }
            },
            resize: { translation in
                if session.resizingID == nil { session.beginResize(item.id, on: saved) }
                session.resize(by: CGSize(width: translation.width / scale, height: translation.height / scale),
                               sizes: sizes)
            },
            endResize: { if let board = session.endResize() { save(board) } }
        )
    }

    /// VoiceOver's way to arrange widgets: remove, each size there is room
    /// for, and a step in each direction.
    @ViewBuilder
    private func accessibilityActions(for item: FaceGridItem, sizes: [WidgetSize], saved: FaceWidgetBoard) -> some View {
        Button("Remove") { remove(item.id, from: saved) }
        ForEach(sizes.filter { $0 != item.size }, id: \.self) { size in
            if let board = saved.resizing(item.id, to: size) {
                Button("Make \(size.title)") { withAnimation(Theme.Motion.settle) { save(board) } }
            }
        }
        ForEach(Self.steps, id: \.name) { step in
            let origin = FaceGridCell(column: item.area.column + step.column, row: item.area.row + step.row)
            if let board = saved.moving(item.id, to: origin) {
                Button(step.name) { withAnimation(Theme.Motion.settle) { save(board) } }
            }
        }
    }

    private static let steps: [(name: String, column: Int, row: Int)] = [
        ("Move Up", 0, -1), ("Move Down", 0, 1), ("Move Left", -1, 0), ("Move Right", 1, 0),
    ]

    private func remove(_ id: UUID, from saved: FaceWidgetBoard) {
        withAnimation(Theme.Motion.standard) {
            if session.selection == id { session.selection = nil }
            save(saved.removing(id))
        }
    }

    private func save(_ board: FaceWidgetBoard) {
        face.saveWidgets(board, legacySize: definition.widgets.legacySize)
    }

    /// Personal widgets show locked until someone is recognized, as in every face preview.
    private func isLocked(_ widget: WidgetDescriptor) -> Bool {
        let showPersonal = services.household.isPersonalContentUnlocked || FaceDebugOptions.forcesPersonal
        return FaceWidgetAccess.of(widget, showPersonal: showPersonal, keepsPersonalPlaces: true) == .locked
    }
}

/// While a widget moves or resizes: every open cell faintly, and the area it
/// would land in outlined. Blocked cells, under the face's own content, show nothing.
private struct WidgetCellGuides: View {
    let grid: FaceGrid
    let scale: CGFloat
    /// Where the widget would land, in the face's coordinates.
    let landing: CGRect?

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Theme.Radius.tile * scale, style: .continuous)
        ZStack(alignment: .topLeading) {
            ForEach(grid.openCells, id: \.self) { cell in
                let frame = Self.scaled(grid.frame(for: cell), scale)
                shape
                    .fill(.white.opacity(0.06))
                    .strokeBorder(.white.opacity(0.22), style: StrokeStyle(lineWidth: 1.5, dash: [6, 5]))
                    .frame(width: frame.width, height: frame.height)
                    .offset(x: frame.minX, y: frame.minY)
            }
            if let landing {
                let frame = Self.scaled(landing, scale)
                shape
                    .fill(.white.opacity(0.18))
                    .strokeBorder(.white.opacity(0.7), lineWidth: 2)
                    .frame(width: frame.width, height: frame.height)
                    .offset(x: frame.minX, y: frame.minY)
                    .animation(Theme.Motion.settle, value: landing)
            }
        }
        .allowsHitTesting(false)
    }

    static func scaled(_ rect: CGRect, _ scale: CGFloat) -> CGRect {
        CGRect(x: rect.minX * scale, y: rect.minY * scale, width: rect.width * scale, height: rect.height * scale)
    }
}
