import HomePadCore
import HomePadUI
import SwiftUI

/// A scaled-down face, for the gallery, My Faces and the editor. It lays the
/// face out at full screen size and scales it, so the thumbnail matches what
/// the face looks like on the wall.
///
/// The editor's preview (`isLive`) is the live face. Every other thumbnail
/// is a card, drawn as a picture of the live face (`FaceStill`), taken again
/// once a minute or when the face changes, so a screen of cards costs no
/// more than one face being built at a time.
///
/// Personal widgets keep their place, drawn locked until someone is
/// recognized (`facesKeepsPersonalPlaces`), so the layout is the real one.
struct FaceThumbnail: View {
    let faceID: String
    var configuration: FaceConfiguration?
    /// Renders at full frame rate (editor preview) instead of thumbnail cadence.
    var isLive = false
    /// The screen the face is laid out on before scaling. The editor passes the
    /// real screen, so its preview matches the wall.
    var canvas: CGSize?
    /// The distance to draw the face at. Across the room by default.
    var proximity: ProximityLevel = .far
    /// The face insets to lay the face out by. Nil uses the wall's at the
    /// wall's size, else the standard ones.
    var insets: EdgeInsets?
    /// Draws the face without its widgets, for the editor's widgets page,
    /// which draws them itself to move them.
    var hidesWidgets = false

    @Environment(FacesRuntime.self) private var runtime
    @Environment(ModuleRegistry.self) private var registry
    @Environment(AppServices.self) private var services
    @Environment(\.displayCondition) private var condition
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.displayScale) private var displayScale

    /// The canvas a face is laid out on before the face on the wall has reported
    /// its size (`FacesRuntime.wallCanvas`): a landscape iPad Pro 13-inch.
    static let canvas = CGSize(width: 1376, height: 1032)

    var body: some View {
        let size = canvas ?? runtime.wallCanvas ?? Self.canvas
        let canvas = CGSize(width: max(size.width, 1), height: max(size.height, 1))
        // At the wall's size, the wall's margins too (they include its burn-in
        // overscan), so a face placed by its insets matches the wall exactly.
        let insets = insets
            ?? (size == runtime.wallCanvas ? runtime.wallInsets ?? Theme.Spacing.screenContent : Theme.Spacing.screenContent)
        GeometryReader { proxy in
            if isLive {
                scaled(canvas: canvas, insets: insets, to: proxy.size)
            } else {
                FaceStill(look: look(canvas: canvas, insets: insets, size: proxy.size), size: proxy.size) {
                    scaled(canvas: canvas, insets: insets, to: proxy.size)
                }
            }
        }
        .aspectRatio(canvas.width / canvas.height, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
        .environment(\.isThumbnail, !isLive)
        .environment(\.proximity, proximity)
        .environment(\.facesKeepsPersonalPlaces, true)
        .allowsHitTesting(false)
        .accessibilityElement()
        .accessibilityLabel(registry.face(faceID)?.title ?? "Face")
    }

    /// The face laid out on `canvas` and scaled to `size`.
    private func scaled(canvas: CGSize, insets: EdgeInsets, to size: CGSize) -> some View {
        content
            .environment(\.faceInsets, insets)
            .environment(\.facesHidesWidgetLayer, hidesWidgets)
            .frame(width: canvas.width, height: canvas.height)
            .scaleEffect(size.width / canvas.width, anchor: .topLeading)
            .frame(width: size.width, height: size.height, alignment: .topLeading)
    }

    /// What the card's picture shows, but the time.
    private func look(canvas: CGSize, insets: EdgeInsets, size: CGSize) -> FaceStills.Look {
        FaceStills.Look(
            configuration: configuration ?? .unsaved(faceID), canvasWidth: canvas.width, canvasHeight: canvas.height,
            insets: [insets.top, insets.leading, insets.bottom, insets.trailing], proximity: proximity,
            hidesWidgets: hidesWidgets, condition: condition, colorScheme: colorScheme,
            showsPersonal: services.household.isPersonalContentUnlocked || FaceDebugOptions.forcesPersonal,
            pixelWidth: Int((size.width * displayScale).rounded())
        )
    }

    @ViewBuilder
    private var content: some View {
        if let definition = FaceCatalog.definition(faceID) {
            FaceHost(definition: definition, runtime: runtime, configuration: configuration ?? .unsaved(faceID))
        } else if let descriptor = registry.face(faceID) {
            descriptor.makeView()
        } else {
            Color.black
        }
    }
}
