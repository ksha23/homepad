import HomePadCore
import HomePadUI
import SwiftUI

/// One widget on the editor's preview, in iPadOS jiggle mode: it wiggles,
/// a minus badge on its corner removes it, dragging it moves it, and once
/// tapped it shows a handle on its bottom trailing corner to drag to another size.
///
/// The widget is drawn at its size on the wall and scaled to the preview,
/// so it looks exactly as it will. The badge and the handle keep their own
/// size, so they stay easy to hit.
struct EditableWidgetTile: View {
    let widget: WidgetDescriptor
    let size: WidgetSize
    /// The widget's size on the face, before scaling.
    let tile: CGSize
    /// The preview's scale.
    let scale: CGFloat
    var isLocked = false
    var isSelected = false
    /// In the air under the finger: larger, still, and without its controls.
    var isLifted = false
    var isNight = false
    /// The placed widget's own settings.
    var settings = WidgetSettings()
    /// The stack at this place, drawn still on the widget it shows, or nil for a single widget.
    var stack: (id: UUID, items: [WidgetStackItem], smartRotate: Bool)?
    /// The sizes its handle snaps between: the widget's, or those all a stack's widgets come in.
    var sizes: [WidgetSize] = []
    let actions: Actions

    /// What the tile asks its canvas to do.
    struct Actions {
        let select: () -> Void
        let remove: () -> Void
        /// The finger moved this far since the drag began, in the preview's points.
        let drag: (CGSize) -> Void
        let drop: () -> Void
        /// The resize handle moved this far since it was grabbed, in the preview's points.
        let resize: (CGSize) -> Void
        let endResize: () -> Void
    }

    @State private var isResizing = false

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: Theme.Radius.tile * scale, style: .continuous)
    }

    var body: some View {
        content
            .frame(width: tile.width, height: tile.height)
            .scaleEffect(scale, anchor: .topLeading)
            .frame(width: tile.width * scale, height: tile.height * scale, alignment: .topLeading)
            .allowsHitTesting(false)
            .nightModeAware()
            .opacity(isNight ? FaceWidgetLayer.nightOpacity : 1)
            .overlay {
                if isSelected, !isLifted {
                    shape.strokeBorder(.white.opacity(0.8), lineWidth: 2)
                }
            }
            .contentShape(shape)
            .gesture(moveGesture)
            .onTapGesture(perform: actions.select)
            .overlay(alignment: .bottomTrailing) {
                if isSelected, !isLifted, sizes.count > 1 {
                    ResizeHandle(cornerRadius: Theme.Radius.tile * scale)
                        .gesture(resizeGesture)
                        .accessibilityHidden(true)
                }
            }
            .overlay(alignment: .topLeading) {
                if !isLifted {
                    RemoveBadge(stack == nil ? "Remove \(widget.title)" : "Remove Stack", action: actions.remove)
                        .offset(x: -10, y: -10)
                }
            }
            .jiggle(true, isPaused: isLifted || isResizing)
            .scaleEffect(isLifted ? WidgetEditSession.liftScale : 1)
    }

    @ViewBuilder
    private var content: some View {
        if let stack {
            FaceStackTile(id: stack.id, items: stack.items, size: size, smartRotate: stack.smartRotate)
        } else {
            FaceWidgetTile(widget: widget, size: size, isLocked: isLocked, settings: settings)
        }
    }

    private var moveGesture: some Gesture {
        DragGesture(minimumDistance: 4, coordinateSpace: .named(WidgetEditCanvas.space))
            .onChanged { value in actions.drag(value.translation) }
            .onEnded { _ in actions.drop() }
    }

    private var resizeGesture: some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .named(WidgetEditCanvas.space))
            .onChanged { value in
                isResizing = true
                actions.resize(value.translation)
            }
            .onEnded { _ in
                isResizing = false
                actions.endResize()
            }
    }
}

/// The handle on a selected widget's bottom trailing corner: a thick white
/// arc that follows the corner, as on the iPadOS Home Screen, in a square
/// big enough to grab.
struct ResizeHandle: View {
    /// The corner radius of the widget it sits on.
    let cornerRadius: CGFloat

    /// How far outside the widget's edge the arc runs.
    private static let outset: CGFloat = 5

    var body: some View {
        CornerArc(radius: cornerRadius + Self.outset)
            .stroke(.white, style: StrokeStyle(lineWidth: 5, lineCap: .round))
            .flattenedShadow(color: .black.opacity(0.35), radius: 3, y: 0)
            .frame(width: cornerRadius + Self.outset, height: cornerRadius + Self.outset)
            .offset(x: Self.outset, y: Self.outset)
            .frame(width: Theme.Size.minTapTarget, height: Theme.Size.minTapTarget, alignment: .bottomTrailing)
            .contentShape(Rectangle())
    }
}

/// A quarter circle in the bottom trailing corner of its frame, from the
/// trailing edge down and around to the bottom edge.
private struct CornerArc: Shape {
    let radius: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.addArc(center: CGPoint(x: rect.maxX - radius, y: rect.maxY - radius), radius: radius,
                    startAngle: .degrees(0), endAngle: .degrees(90), clockwise: false)
        return path
    }
}
