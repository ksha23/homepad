import HomePadCore
import HomePadUI
import SwiftUI

/// The face editor, modeled on watchOS: a big live preview, one page per
/// option (Style, Color, Widgets...), and the controls for the open page
/// under it. Swipe the preview to change pages, tap a card to change the
/// value, and tap a slot to pick from a gallery.
///
/// The preview lays the face out at the real screen's size, so it matches the
/// wall, and shows it from across the room or up close. A page whose option
/// only shows at one distance switches to it.
///
/// On the widgets page the preview is where widgets are arranged, like the
/// iPadOS Home Screen in jiggle mode (`WidgetEditCanvas`): drag to move, drag
/// the selected widget's corner to resize, tap the minus to remove, and Add
/// Widget under the preview for the gallery. Landscape and portrait each
/// have their own arrangement, picked beside the distance.
///
/// Presented full screen with `.coverScreenMargin()`.
struct FaceEditorView: View {
    let owner: FaceOwner
    @State private var face: FaceConfiguration
    @State private var page: Int
    @State private var distance: EditorDistanceState
    /// The window's size, measured, for before the face on the wall has reported its own.
    @State private var screen = FaceThumbnail.canvas
    /// The widgets page's selection and the drag or resize under way.
    @State private var widgets = WidgetEditSession()
    /// The orientation the widgets page arranges. Nil follows the screen.
    @State private var widgetOrientation: FaceGrid.Orientation?
    @State private var widgetGallery: WidgetGalleryRequest?
    /// The widget Edit Widget is open for.
    @State private var widgetSettings: FaceWidgetSettingsRequest?

    @Environment(FacesRuntime.self) private var runtime
    @Environment(ModuleRegistry.self) private var registry
    @Environment(AppServices.self) private var services
    @Environment(\.dismiss) private var dismiss
    /// What Done, Show Now and the close button do once the face is saved (or not, for close). Nil
    /// dismisses the editor's cover. Holding the face draws the editor straight in the Faces app, and
    /// closing it closes the app.
    private let onClose: (@MainActor () -> Void)?
    @Environment(\.colorScheme) private var colorScheme

    /// - Parameters:
    ///   - startDistance: Shows the preview at this distance, as if picked by hand.
    init(face: FaceConfiguration, owner: FaceOwner, startPage: Int = 0, startDistance: EditorDistance? = nil,
         onClose: (@MainActor () -> Void)? = nil) {
        self.owner = owner
        self.onClose = onClose
        // Widgets in the slots of a face saved before the grid move onto it,
        // so the widgets page and the preview show them where they are.
        // `-HomePadFacesWidgets` and `-HomePadFacesMiniWidget` apply here as on
        // the My Faces card it was opened from, in debug builds.
        var face = FaceDebugOptions.withWidgetOverride(face)
        if let definition = FaceCatalog.definition(face.faceID) {
            face.adoptWidgetGrid(legacySize: definition.widgets.legacySize)
        }
        _face = State(initialValue: face)
        _page = State(initialValue: startPage)
        var distance = EditorDistanceState()
        let options = FaceCatalog.definition(face.faceID)?.options(for: face) ?? []
        distance.open(options.indices.contains(startPage) ? options[startPage] : nil)
        if let startDistance { distance.pick(startDistance) }
        _distance = State(initialValue: distance)
        // Made as the editor is presented, so the frame rate covers building it.
        FacesPerfTrace.moment("editor")
    }

    var body: some View {
        let definition = FaceCatalog.definition(face.faceID)
        let options = definition?.options(for: face) ?? []
        let option = options.indices.contains(page) ? options[page] : nil
        let isWidgetPage = option?.isWidgetGrid == true
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            AppHeader(definition?.title ?? "Face", onClose: { close() }) {
                GlassCapsuleButton("Show Now") { save(makingCurrent: true) }
                GlassCapsuleButton("Done", isProminent: true) { save(makingCurrent: false) }
            }
            GeometryReader { proxy in
                let isWide = proxy.size.width > proxy.size.height
                let controls = EditorMetrics.controlsHeight(
                    for: option, screen: canvas, width: proxy.size.width, height: proxy.size.height)
                VStack(spacing: Theme.Spacing.m) {
                    preview(pageCount: options.count, widgetsOf: isWidgetPage ? definition : nil)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        // On the preview rather than with the gallery's sheet, so the two never share one view.
                        .sheet(item: $widgetSettings) { request in
                            if let definition {
                                FaceEditWidgetSheet(request: request, definition: definition, face: $face,
                                                    board: widgetBoard(definition))
                                    .presentationSizing(.page)
                            }
                        }
                    EditorBar(pages: options, page: $page, distance: distanceBinding,
                              orientation: isWidgetPage ? orientationBinding : nil, isWide: isWide)
                    controlsView(option, definition: definition)
                        .frame(height: controls)
                }
            }
        }
        .padding(Theme.Spacing.l)
        .background {
            // Full bleed, so it measures the whole window: the screen the face fills.
            Color.screenBackground
                .ignoresSafeArea()
                .onGeometryChange(for: CGSize.self) { $0.size } action: { screen = $0 }
        }
        .onChange(of: page) {
            withAnimation(Theme.Motion.proximity) { distance.open(option) }
            widgets.selection = nil
            FacesPerfTrace.moment("editor.page")
        }
        .onChange(of: distance.shown) { FacesPerfTrace.moment("editor.distance") }
        .sheet(item: $widgetGallery) { request in
            if let definition {
                FaceWidgetGallerySheet(board: widgetBoard(definition), opening: request.widgetID, size: request.size) { widget, size in
                    addWidget(widget, size: size, definition: definition)
                } onAddStack: { size, members in
                    addStack(members, size: size, definition: definition)
                }
                .presentationSizing(.page)
            }
        }
        .task(id: isWidgetPage) {
            guard isWidgetPage, let definition, let debug = WidgetEditDebug.fromLaunchArguments() else { return }
            if let orientation = debug.orientation { widgetOrientation = orientation }
            // Once the preview has measured the screen.
            try? await Task.sleep(for: .milliseconds(800))
            debug.apply(to: widgets, board: widgetBoard(definition), sizes: { registry.widget($0)?.supportedSizes ?? [] })
            widgetGallery = debug.gallery
        }
    }

    // MARK: Preview

    /// - Parameter definition: The face whose widgets the preview arranges, on the widgets page.
    private func preview(pageCount: Int, widgetsOf definition: FaceDefinition?) -> some View {
        let canvas = definition == nil ? canvas : widgetCanvas
        return FaceThumbnail(faceID: face.faceID, configuration: face, isLive: true, canvas: canvas,
                             proximity: distance.shown.proximity, insets: faceInsets, hidesWidgets: definition != nil)
            // The widgets being arranged read the face's backdrop, as on the wall.
            .overlayPreferenceValue(BackdropToneKey.self) { tone in
                if let definition {
                    WidgetEditCanvas(definition: definition, face: $face, canvas: canvas, insets: faceInsets,
                                     session: widgets)
                        .glassBackdrop(tone)
                }
            }
            // A shadow of the card's shape, drawn once. On the live face it
            // was drawn again on every frame the preview animated. It is
            // lighter on a white page, where the dark one made a gray halo.
            .background {
                RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                    .fill(.black)
                    .flattenedShadow(color: .black.opacity(colorScheme == .dark ? 0.5 : 0.18), radius: 24, y: 12)
            }
            .overlay {
                RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                    .strokeBorder(.primary.opacity(0.15), lineWidth: 1)
            }
            // Switching the distance moves the face between its far and near
            // layouts on the same curve as the face on the wall.
            .animation(Theme.Motion.proximity, value: distance.shown)
            .contentShape(Rectangle())
            // On the widgets page a drag moves a widget instead.
            .gesture(pageSwipe(count: pageCount), isEnabled: definition == nil)
    }

    private func pageSwipe(count: Int) -> some Gesture {
        DragGesture(minimumDistance: 30).onEnded { value in
            guard abs(value.translation.width) > abs(value.translation.height), count > 1 else { return }
            let step = value.translation.width < 0 ? 1 : -1
            withAnimation(Theme.Motion.standard) { page = min(max(page + step, 0), count - 1) }
        }
    }

    // MARK: Controls

    @ViewBuilder
    private func controlsView(_ option: FaceOption?, definition: FaceDefinition?) -> some View {
        if let option, option.isWidgetGrid, let definition {
            let board = widgetBoard(definition)
            let selected = widgets.selection.flatMap { board.item($0) }
            let widget = selected.flatMap { registry.widget($0.widgetID) }
            let selectsStack = selected.map { face.widgetStack(for: $0.id, legacySize: definition.widgets.legacySize) != nil } ?? false
            WidgetsPage(board: board, miniWidget: $face.miniWidget,
                        selectedWithSettings: widget?.hasSettings == true ? widget : nil,
                        selectsStack: selectsStack,
                        isSelectionLocked: widget.map { FaceEditWidgetSheet.isLocked($0, household: services.household) } ?? false,
                        onAdd: { widgetGallery = WidgetGalleryRequest() },
                        onEditWidget: { if let selected { widgetSettings = FaceWidgetSettingsRequest(id: selected.id) } })
                .animation(Theme.Motion.standard, value: widgets.selection)
                .transition(.opacity)
        } else if let option {
            OptionPage(option: option, face: $face, screen: canvas, proximity: distance.shown.proximity)
                .id(page)
                .transition(.opacity)
        } else {
            Text("This face has nothing to customize.")
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var distanceBinding: Binding<EditorDistance> {
        Binding(get: { distance.shown }, set: { picked in
            withAnimation(Theme.Motion.proximity) { distance.pick(picked) }
        })
    }

    /// The size faces are laid out at: the face on the wall's own size, so the
    /// preview and the cards decide everything (such as the depth effect) as it
    /// does. Turned when the iPad has turned since the face last reported it.
    private var canvas: CGSize {
        guard let wall = runtime.wallCanvas else { return screen }
        return FaceGrid.Orientation(wall) == FaceGrid.Orientation(screen) ? wall : CGSize(width: wall.height, height: wall.width)
    }

    /// The face insets the preview lays the face out by: the wall's, which
    /// include its burn-in overscan, so widgets land on the wall where they do here.
    private var faceInsets: EdgeInsets {
        runtime.wallInsets ?? Theme.Spacing.screenContent
    }

    // MARK: Widgets

    /// The size the widgets page lays the face out at: the canvas, turned to
    /// the orientation picked there.
    private var widgetCanvas: CGSize {
        guard let widgetOrientation, FaceGrid.Orientation(canvas) != widgetOrientation else { return canvas }
        return CGSize(width: canvas.height, height: canvas.width)
    }

    private var orientationBinding: Binding<FaceGrid.Orientation> {
        Binding(get: { FaceGrid.Orientation(widgetCanvas) }, set: { picked in
            widgets.selection = nil
            withAnimation(Theme.Motion.screen) { widgetOrientation = picked }
        })
    }

    /// The face's widgets as saved, in the orientation being arranged.
    private func widgetBoard(_ definition: FaceDefinition) -> FaceWidgetBoard {
        FaceWidgetBoard.face(definition, configuration: face, size: widgetCanvas, insets: faceInsets, registry: registry)
    }

    /// Adds a widget from the gallery, selected: in the first open area for its size, or
    /// nearest the face's top leading corner for a widget anchored there (the glance).
    private func addWidget(_ widget: WidgetDescriptor, size: WidgetSize, definition: FaceDefinition) {
        let id = UUID()
        guard let board = widgetBoard(definition).adding(widget.id, size: size, id: id, anchor: widget.anchor) else { return }
        widgetGallery = nil
        withAnimation(Theme.Motion.settle) {
            face.saveWidgets(board, legacySize: definition.widgets.legacySize)
            widgets.selection = id
        }
    }

    /// Adds a Smart Stack from the gallery, selected, in the first open area
    /// for its size: a placement for its first widget that holds them all.
    private func addStack(_ members: [WidgetDescriptor], size: WidgetSize, definition: FaceDefinition) {
        guard let first = members.first else { return }
        let id = UUID()
        let legacySize = definition.widgets.legacySize
        guard let board = widgetBoard(definition).adding(first.id, size: size, id: id) else { return }
        widgetGallery = nil
        withAnimation(Theme.Motion.settle) {
            face.saveWidgets(board, legacySize: legacySize)
            face.setWidgetStack(.of(members.map(\.id)), for: id, legacySize: legacySize)
            widgets.selection = id
        }
    }

    private func save(makingCurrent: Bool) {
        runtime.library.save(face, for: owner)
        if makingCurrent { runtime.library.makeCurrent(face.id, for: owner) }
        close()
    }

    private func close() {
        if let onClose { onClose() } else { dismiss() }
    }
}
