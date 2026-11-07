import HomePadCore
import HomePadUI
import SwiftUI

/// One face drawn with one configuration: a page of the face on the wall
/// (`FacePager`), or the face a thumbnail, the editor or Smart Rotation shows
/// (`FaceHost`). It injects shared face state and draws the face's widgets.
///
/// Someone walking up or away changes `\.proximity` without an animation of
/// its own, so every face's change is animated here on one curve,
/// `Theme.Motion.proximity`: the big fact shrinking, the detail fading in and
/// whatever else moves with them. Faces add no curve of their own for it.
///
/// At night the face on the wall keeps its far layout whoever walks up
/// (`shownProximity`), like HomeView's night face: one big fact in one red.
/// The near layouts add events, forecasts and other small text that would
/// have to be dim to keep the room dark, and dim red text does not read.
/// Previews in the editor and My Faces still show both distances.
///
/// The widgets are drawn over the face at every distance (`FaceWidgetLayer`).
/// For a face with a widget area the face gets insets that keep its content
/// beside them (`FaceWidgetSupport.widgetRoom`). The widgets' glass takes its
/// light or dark look from the tone the face reports for its backdrop
/// (`backdropTone(_:)`).
///
/// The face's mini widget is drawn here too, in the face's top margin at its
/// leading side (`FaceMiniWidgetLayer`), rather than by the shell: it belongs
/// to the saved face, so it pages with the face, drifts with it and shows in
/// every preview. It fits the margin, so the face's content never moves for it.
struct HostedFace: View {
    let definition: FaceDefinition
    let runtime: FacesRuntime
    /// The saved configuration to draw, with any debug overrides applied.
    let configuration: FaceConfiguration
    /// True for the face on the wall and its frosted copy behind the Home Screen.
    let isOnWall: Bool

    @Environment(AppServices.self) private var services
    @Environment(ModuleRegistry.self) private var registry
    @Environment(\.displayCondition) private var condition
    @Environment(\.isFrosted) private var isFrosted
    @Environment(\.proximity) private var proximity
    @Environment(\.faceInsets) private var faceInsets
    @Environment(\.facesHidesWidgetLayer) private var hidesWidgetLayer
    @Environment(\.faceNowPlayingRoom) private var nowPlayingRoom

    private static let launchTimeOffset = FaceDebugOptions.timeOffset()

    var body: some View {
        let shownProximity = Self.shownProximity(proximity, condition: displayCondition, isOnWall: isOnWall)
        GeometryReader { proxy in
            let board = widgetBoard(size: proxy.size)
            let hasWidgets = board?.items.isEmpty == false
            let room = definition.widgets.widgetRoom(size: proxy.size, insets: gridInsets, hasWidgets: hasWidgets)
            definition.makeView()
                .environment(\.faceInsets, Self.adding(room, to: faceInsets))
                .environment(\.faceKeepClear, Self.adding(EdgeInsets(top: nowPlayingRoom, leading: 0, bottom: 0, trailing: 0), to: room))
                .environment(\.faceHasWidgets, hasWidgets)
                .environment(\.faceProfileZone, FaceWidgetSupport.profileZone(size: proxy.size, insets: gridInsets))
                .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
                // The widgets read the tone the face reports for its backdrop, so
                // their glass is dark over a dark face and light over a bright one.
                .overlayPreferenceValue(BackdropToneKey.self, alignment: .topLeading) { tone in
                    if !isFrosted {
                        ZStack(alignment: .topLeading) {
                            if let board, !hidesWidgetLayer {
                                FaceWidgetLayer(board: board, layout: configuration.widgets(legacySize: definition.widgets.legacySize),
                                                opensApps: isOnWall)
                            }
                            // Over the editor's widgets page too, so the corner it keeps shows what keeps it.
                            if let miniWidget {
                                FaceMiniWidgetLayer(placement: miniWidget,
                                                    frame: FaceWidgetSupport.miniWidgetFrame(size: proxy.size, insets: gridInsets),
                                                    opensApps: isOnWall)
                            }
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                        .glassBackdrop(tone)
                        .environment(\.displayCondition, definition.widgets.isAlwaysNight ? .night : displayCondition)
                    }
                }
        }
            .environment(\.faceConfiguration, configuration)
            .environment(\.isInsideFaceHost, true)
            .environment(\.displayCondition, displayCondition)
            .environment(\.faceTimeOffset, Self.launchTimeOffset)
            .environment(\.facesShowPersonal, services.household.isPersonalContentUnlocked || FaceDebugOptions.forcesPersonal)
            .environment(runtime)
            .environment(\.proximity, shownProximity)
            .animation(Theme.Motion.proximity, value: shownProximity)
            .background(Color.black.ignoresSafeArea())
            .onGeometryChange(for: CGSize.self) { $0.size } action: { size in
                // The face on the wall reports its size and insets, so thumbnails
                // match it. The frosted copy behind the Home Screen has another size.
                // The insets go without the Now Playing pill, which previews do not show.
                guard isOnWall, !isFrosted, size.width > 0 else { return }
                if runtime.wallCanvas != size { runtime.wallCanvas = size }
                if runtime.wallInsets != gridInsets { runtime.wallInsets = gridInsets }
            }
    }

    /// The display condition the face draws for, red when the debug night option asks.
    private var displayCondition: DisplayCondition {
        FaceDebugOptions.forcesNight ? .night : condition
    }

    /// The distance a face lays itself out for. On the wall at night, and in
    /// its frosted copy behind the Home Screen, that is always far. A nested
    /// face (Smart Rotation's) takes it from the host around it.
    static func shownProximity(_ proximity: ProximityLevel, condition: DisplayCondition,
                               isOnWall: Bool) -> ProximityLevel {
        isOnWall && condition == .night ? .far : proximity
    }

    /// The face insets without the room the Now Playing pill takes while it
    /// shows. The widget grid keeps to them, so widgets stay where they are
    /// when music starts or stops, and it keeps the cells under the pill free.
    private var gridInsets: EdgeInsets {
        EdgeInsets(top: faceInsets.top - nowPlayingRoom, leading: faceInsets.leading,
                   bottom: faceInsets.bottom, trailing: faceInsets.trailing)
    }

    /// The mini widget in the face's top left corner, or nil without one. A
    /// face without widgets of its own (Smart Rotation) has none either: the
    /// face it shows draws its own.
    private var miniWidget: MiniWidgetPlacement? {
        // Always the smallest size on a face, whatever an earlier version saved.
        guard definition.widgets.allowsWidgets, let saved = configuration.miniWidget else { return nil }
        return MiniWidgetPlacement(widgetID: saved.widgetID, size: .small)
    }

    /// The face's widgets at a size, or nil for a face without widgets of its own.
    private func widgetBoard(size: CGSize) -> FaceWidgetBoard? {
        guard definition.widgets.allowsWidgets else { return nil }
        return FaceWidgetBoard.face(definition, configuration: configuration, size: size, insets: gridInsets,
                                    registry: registry)
    }

    private static func adding(_ room: EdgeInsets, to insets: EdgeInsets) -> EdgeInsets {
        EdgeInsets(top: insets.top + room.top, leading: insets.leading + room.leading,
                   bottom: insets.bottom + room.bottom, trailing: insets.trailing + room.trailing)
    }
}
