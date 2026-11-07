import HomePadCore
import HomePadUI
import SwiftUI

/// The Faces app, HomePad's "My Faces": the saved faces for the household or
/// for one member. Tap a face to show it. Customize under each face opens the
/// editor, Add Face opens the gallery of all faces, and holding a face offers
/// Customize and Remove. It reopens on the owner it was showing, or everyone's
/// once that member is gone.
///
/// Holding the face on the wall opens the editor for that face at once
/// (`FacesRuntime.editsWallFace`), drawn straight in the app rather than in a
/// cover that slides up, since the shell fades the app in from the face.
/// Closing the editor closes the app, back to the face, with the same fade.
struct FacesAppView: View {
    @Environment(FacesRuntime.self) private var runtime
    @Environment(AppServices.self) private var services
    @Environment(\.closeApp) private var closeApp
    @AppState(FacesAppState.owner) private var savedOwner
    @State private var editing: EditorTarget?
    /// The face on the wall, while the app shows its editor after a hold on the face.
    @State private var wallEdit: EditorTarget?
    @State private var isAddingFace = false
    /// A face just added from the gallery, edited once the gallery has closed.
    @State private var addedFace: EditorTarget?

    /// Made as the app is built, so the frame rate covers building My Faces.
    init() {
        FacesPerfTrace.moment("open")
    }

    var body: some View {
        // Read from the request too, so the very first frame is the editor and never My Faces.
        if let target = wallEdit ?? (runtime.editsWallFace ? wallTarget : nil) {
            FaceEditorView(face: target.face, owner: target.owner, onClose: { closeApp?() })
                .id(target.face.id)
                .onChange(of: runtime.editsWallFace, initial: true) { _, edits in takeWallRequest(edits) }
                // Kept while the app fades out, and forgotten once it has gone, so the next open is fresh.
                .onDisappear { wallEdit = nil }
        } else {
            myFaces
                .onChange(of: runtime.editsWallFace, initial: true) { _, edits in takeWallRequest(edits) }
        }
    }

    /// The editor for the face the wall shows (`FacesRuntime.wallFace`), as saved now, for whoever the
    /// wall shows faces for.
    private var wallTarget: EditorTarget {
        let library = runtime.library
        let owner = library.activeOwner
        let shown = runtime.wallFace
        let face = shown.flatMap { shown in library.list(for: owner).faces.first { $0.id == shown.id } }
            ?? shown ?? library.current(for: owner)
        return EditorTarget(face: face, owner: owner)
    }

    private func takeWallRequest(_ edits: Bool) {
        guard edits else { return }
        runtime.editsWallFace = false
        wallEdit = wallTarget
    }

    @ViewBuilder
    private var myFaces: some View {
        let library = runtime.library
        let list = library.list(for: owner)
        let currentID = library.current(for: owner).id
        AppScreen("Faces", accessory: {
            GlassCapsuleButton("Add Face", systemImage: "plus", isProminent: true) { isAddingFace = true }
        }, titleAccessory: {
            OwnerPicker(owner: Binding(get: { owner }, set: { savedOwner = $0 }))
        }, content: {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                    SectionHeader(owner == .household ? "My Faces" : "Their Faces", systemImage: "square.stack")
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 300), spacing: Theme.Spacing.l)], spacing: Theme.Spacing.l) {
                        ForEach(list.faces) { face in
                            SavedFaceCard(
                                face: face, isCurrent: face.id == currentID,
                                onShow: { withAnimation(Theme.Motion.standard) { library.makeCurrent(face.id, for: owner) } },
                                onCustomize: { editing = EditorTarget(face: face, owner: owner) }
                            )
                            .contextMenu { menu(for: face) }
                        }
                    }
                    .sensoryFeedback(.selection, trigger: currentID)
                    Text("Tap a face to show it. On the face itself, swipe left or right to switch between these. Hold a face here to customize or remove it.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .padding(.top, Theme.Spacing.s)
                }
                .padding(.bottom, Theme.Spacing.xl)
            }
            .facesScrollTrace("myFaces")
            // Covered by the editor or the gallery, the cards keep the pictures they have.
            .environment(\.facesPausesStills, editing != nil || isAddingFace)
        })
        .fullScreenCover(item: $editing) { target in
            FaceEditorView(face: target.face, owner: target.owner, startPage: target.page, startDistance: target.distance)
                .environment(runtime)
                .coverScreenMargin()
                .coverHomeBar()
                .modifier(CoverForcedLandscape())
        }
        .sheet(isPresented: $isAddingFace, onDismiss: openAddedFace) {
            FaceGallerySheet { faceID in
                addedFace = EditorTarget(face: library.add(faceID: faceID, to: owner), owner: owner)
                isAddingFace = false
            }
            .presentationSizing(.page)
        }
        .task { applyDebugLaunchArguments() }
    }

    /// The owner picked last, or everyone once that member has left the household.
    private var owner: FaceOwner {
        guard case .member(let id) = savedOwner, !services.household.members.contains(where: { $0.id == id }) else {
            return savedOwner
        }
        return .household
    }

    /// Opens the editor for a face added from the gallery. Presenting the
    /// full-screen editor while the gallery sheet is still closing would drop it.
    private func openAddedFace() {
        guard let addedFace else { return }
        self.addedFace = nil
        editing = addedFace
    }

    @ViewBuilder
    private func menu(for face: FaceConfiguration) -> some View {
        Button { runtime.library.makeCurrent(face.id, for: owner) } label: { Label("Show Now", systemImage: "checkmark.circle") }
        Button { editing = EditorTarget(face: face, owner: owner) } label: { Label("Customize", systemImage: "slider.horizontal.3") }
        Button(role: .destructive) { runtime.library.remove(face.id, from: owner) } label: { Label("Remove", systemImage: "minus.circle") }
            .disabled(runtime.library.list(for: owner).faces.count < 2)
    }

    /// Debug launch arguments for screenshots:
    ///   -HomePadFacesEdit <faceID>   open the editor for the first saved face of that kind
    ///   -HomePadFacesEditPage <n>    start the editor on page n
    ///   -HomePadFacesEditDistance near|far   preview the face up close or across the room
    ///   -HomePadFacesEditWidgets YES  start the editor on the widgets page (`WidgetEditDebug` lists more)
    ///   (-HomePadFacesStyle, -HomePadFacesColors and -HomePadFacesWidgets apply to the face opened in the editor too)
    ///   -HomePadFacesAdd YES         open the gallery of all faces
    private func applyDebugLaunchArguments() {
        #if DEBUG
        let defaults = UserDefaults.standard
        if let faceID = defaults.string(forKey: "HomePadFacesEdit") {
            let saved = runtime.library.configuration(forFace: faceID, owner: owner)
            let face = FaceDebugOptions.withWallOverrides(FaceDebugOptions.withStyleOverride(
                saved.id == FaceConfiguration.unsaved(faceID).id ? FaceConfiguration(faceID: faceID) : saved))
            var page = defaults.integer(forKey: "HomePadFacesEditPage")
            if defaults.bool(forKey: "HomePadFacesEditWidgets"),
               let index = FaceCatalog.definition(faceID)?.options(for: face).firstIndex(where: \.isWidgetGrid) {
                page = index
            }
            editing = EditorTarget(face: face, owner: owner, page: page,
                                   distance: defaults.string(forKey: "HomePadFacesEditDistance").flatMap(EditorDistance.init(rawValue:)))
        }
        if defaults.bool(forKey: "HomePadFacesAdd") { isAddingFace = true }
        #endif
    }
}

/// What the editor is editing.
struct EditorTarget: Identifiable {
    var face: FaceConfiguration
    var owner: FaceOwner
    var page = 0
    /// The distance to preview at, as if picked by hand. Nil starts across the room.
    var distance: EditorDistance?
    var id: UUID { face.id }
}
