import HomePadCore
import HomePadUI
import SwiftUI

/// The face on the wall: the saved faces as pages, swiped between like the
/// Home Screen's pages. The face follows the finger with the next one beside
/// it, a short slow swipe springs back, and a long or quick one settles on
/// the next face. The faces go round: past the last comes the first, and
/// back from the first comes the last. One saved face does not page.
///
/// The pager lays out five pages, the face at rest and the two faces before
/// and after it (`FacePageWindow`), so a quick second flick, made while the
/// first still glides, has a face to land on. When the pages rest on a face beside the
/// middle one, the window moves along under it in the same update, and the
/// scroll position stays on that face's page. That page and the face drawn on
/// it are the same views as before, so nothing on screen changes, and a face
/// with motion of its own carries on. Only the page beyond is new.
///
/// The page on screen lives here, so a swipe changes nothing outside until
/// the pages come to rest. Then the face they rest on becomes the current
/// saved face and the shell is asked to show its kind (`.showFace`). The
/// shell answers by handing this same view that kind (see `FaceHost`), which
/// moves nothing, since it is the kind of the face on screen. Only a request
/// from outside moves the pages: the shell showing another kind (the
/// assistant, a shortcut), or another saved face of the kind on screen
/// becoming current (My Faces).
///
/// The faces beside the one at rest are built while the pages rest, not as a
/// swipe reveals them: building a face as it slid in held up the first frames
/// of the swipe. They hold still while none of them shows (`\.faceIsBeside`)
/// and start moving as the first points of them show, so a face is already
/// running when the pages rest on it. Each page clips what its face draws to
/// the page, so nothing shows on its neighbour. Nothing on a page reads the
/// scroll position, so moving the pages redraws no face.
struct FacePager: View {
    /// The face kind the shell shows.
    let faceID: String
    let runtime: FacesRuntime

    @Environment(AppServices.self) private var services

    /// The pages laid out, the face at rest in the middle.
    @State private var window: FacePageWindow
    /// Where the pages are scrolled to. The scroll view keeps the page on
    /// screen in it as the pages move, and the pager sets its offset when it
    /// lays out a new window.
    @State private var position: ScrollPosition
    /// The width of one page, the pager's own width.
    @State private var pageWidth: CGFloat = 0
    /// The pages with some of their face on screen.
    @State private var visiblePages: Set<FacePageWindow.Page.ID> = []

    init(faceID: String, runtime: FacesRuntime) {
        self.faceID = faceID
        self.runtime = runtime
        let library = runtime.library
        let owner = library.activeOwner
        let start = library.configuration(forFace: faceID, owner: owner).id
        let faces = Self.faces(library: library, owner: owner, faceID: faceID)
        let window = FacePageWindow(around: start, order: faces.map(\.id))
        _window = State(initialValue: window)
        _position = State(initialValue: ScrollPosition(id: window.resting.id))
    }

    var body: some View {
        let faces = faces
        GeometryReader { proxy in
            ScrollView(.horizontal) {
                HStack(spacing: 0) {
                    ForEach(window.pages) { page in
                        self.page(page, faces: faces)
                            .frame(width: proxy.size.width, height: proxy.size.height)
                            // A face that draws past its page shows only on its own page.
                            .clipped()
                            // VoiceOver reads the face at rest, not the ones beside it. Taken from
                            // the window, not from the page the scroll view reports, which can
                            // name another page while it places the first layout.
                            .accessibilityHidden(page != window.resting)
                            // Only the face at rest is where an app opens from. The faces beside it can be
                            // the same face with the same widgets, which reported under the same IDs a page
                            // to the side, so a tap on a widget found nothing under it.
                            .transformPreference(ZoomSourcesKey.self) { if page != window.resting { $0 = [:] } }
                            // A face beside the one at rest starts moving as soon as the first
                            // points of it show, so it is already running when the pages rest on it.
                            .onScrollVisibilityChange(threshold: 0.01) { isVisible in
                                if isVisible { visiblePages.insert(page.id) } else { visiblePages.remove(page.id) }
                            }
                    }
                }
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.paging)
            .scrollPosition($position)
            // The first layout starts on the middle page, as the Home Screen's start on theirs.
            .defaultScrollAnchor(window.pages.count > 1 ? UnitPoint(x: 0.5, y: 0) : .topLeading, for: .initialOffset)
            .scrollIndicators(.hidden)
            .scrollDisabled(window.pages.count < 2)
            .onScrollPhaseChange { old, phase in
                if PhotoTrace.trace.isEnabled {
                    let on = position.viewID(type: FacePageWindow.Page.ID.self).flatMap { id in window.pages.firstIndex { $0.id == id } }
                    PhotoTrace.trace.log("pager \(old) -> \(phase), on page \(on.map(String.init) ?? "-") of \(window.pages.count)")
                }
                if phase == .idle { settle(faces) }
            }
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { pageWidth = $0 }
        }
        // The face holding the wall edits, as the pages rest on it.
        .onChange(of: window.resting.faceID, initial: true) { _, id in
            runtime.wallFace = faces.first { $0.id == id }
        }
        .onChange(of: faces.map(\.id)) { _, order in
            // Saved faces were added, removed or reordered: the faces beside the one at rest follow.
            move(to: window.centered(on: window.resting, order: order))
        }
        .onChange(of: faceID) { _, kind in
            // The shell catching up with the face the pages rest on moves nothing.
            // Any other kind is a request from outside.
            guard kind != restingKind else { return }
            show(library.configuration(forFace: kind, owner: owner).id)
        }
        .onChange(of: library.current(for: owner).id) { _, id in
            // Another saved face of the kind on screen became current. Counted only
            // once the shell has caught up: right after the pages settle, the
            // library names the new face while the shell still shows the old kind.
            guard id != window.resting.faceID, faceID == restingKind,
                  library.current(for: owner).faceID == faceID else { return }
            show(id)
        }
    }

    private var library: FaceLibrary { runtime.library }

    /// Whose saved faces the pages are.
    private var owner: FaceOwner { library.activeOwner }

    /// The faces in page order.
    private var faces: [FaceConfiguration] {
        Self.faces(library: library, owner: owner, faceID: faceID)
    }

    /// The saved faces, then the face the shell shows when none of them is
    /// that kind (the assistant can show any kind).
    private static func faces(library: FaceLibrary, owner: FaceOwner, faceID: String) -> [FaceConfiguration] {
        var faces = library.list(for: owner).faces
        let shown = library.configuration(forFace: faceID, owner: owner)
        if !faces.contains(where: { $0.id == shown.id }) { faces.append(shown) }
        return faces
    }

    /// The kind of the face the pages rest on. The shell has caught up with
    /// the pages when it shows this kind.
    private var restingKind: String? {
        faces.first { $0.id == window.resting.faceID }?.faceID
    }

    /// One page's face as it draws on the wall. Debug overrides: the style, colors and widgets.
    ///
    /// Only the face at rest reports how bright its backdrop is. The first report wins
    /// (`BackdropToneKey`), so the face to its left set the glass on the face and the tint of the
    /// Home Screen's wallpaper.
    @ViewBuilder
    private func page(_ page: FacePageWindow.Page, faces: [FaceConfiguration]) -> some View {
        let isResting = page == window.resting
        if let face = faces.first(where: { $0.id == page.faceID }), let definition = FaceCatalog.definition(face.faceID) {
            HostedFace(definition: definition, runtime: runtime,
                       configuration: FaceDebugOptions.withStyleOverride(FaceDebugOptions.withWallOverrides(face)),
                       isOnWall: true)
                .environment(\.faceIsBeside, !isResting && !visiblePages.contains(page.id))
                .transformPreference(BackdropToneKey.self) { tone in
                    if !isResting { tone = nil }
                }
        } else {
            Color.black
        }
    }

    /// The pages came to rest. On a page beside the middle one, the window
    /// moves along to it, that face becomes the current saved face and the
    /// shell shows its kind.
    private func settle(_ faces: [FaceConfiguration]) {
        guard let id = position.viewID(type: FacePageWindow.Page.ID.self), id != window.resting.id,
              let page = window.pages.first(where: { $0.id == id }),
              let face = faces.first(where: { $0.id == page.faceID }) else { return }
        move(to: window.centered(on: page, order: faces.map(\.id)))
        PhotoTrace.trace.log("pager settled on \(face.faceID)")
        if library.list(for: owner).faces.contains(where: { $0.id == face.id }) {
            library.makeCurrent(face.id, for: owner)
        }
        services.events.post(.showFace(id: face.faceID))
    }

    /// Moves the pages straight to a face asked for from outside.
    private func show(_ id: UUID) {
        move(to: FacePageWindow(around: id, order: faces.map(\.id)))
    }

    /// Lays out a new window and puts its middle page on screen in the same
    /// update, by offset: the page on screen before may be that same page,
    /// whose place in the window changed.
    private func move(to new: FacePageWindow) {
        guard new != window else { return }
        let index = new.pages.firstIndex(of: new.resting) ?? 0
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            window = new
            position.scrollTo(x: CGFloat(index) * pageWidth)
        }
    }
}
