import HomePadCore
import HomePadUI
import SwiftUI

/// The widgets on a face's grid, drawn over the face by `HostedFace` at every
/// distance, so walking up or away never takes them off the wall.
///
/// Personal widgets follow `FaceWidgetAccess`: left out on the wall until
/// someone is recognized, with their cells left empty so nothing moves, and
/// drawn locked in previews. In night mode the widgets turn red with the face
/// and dim further, so they do not light up a dark room.
///
/// On the wall a tap on a widget, outside its own buttons, opens its app, as
/// on the Home Screen. Without it the tap reached the face, which went to the
/// Home Screen instead. Each widget there reports itself as a zoom source, so
/// the app grows out of it and closes back into it on the face.
///
/// A widget stack (`FaceStackTile`) flips with a vertical swipe on the wall,
/// and a tap opens the app of the widget on top.
struct FaceWidgetLayer: View {
    let board: FaceWidgetBoard
    /// The face's widget layout, for each widget's own settings.
    let layout: FaceWidgetLayout
    /// True for the face on the wall. Previews in the editor and My Faces take taps for themselves.
    var opensApps = false

    @Environment(AppServices.self) private var services
    @Environment(ModuleRegistry.self) private var registry
    @Environment(\.facesShowPersonal) private var showPersonal
    @Environment(\.facesKeepsPersonalPlaces) private var keepsPersonalPlaces
    @Environment(\.displayCondition) private var condition

    var body: some View {
        ZStack(alignment: .topLeading) {
            ForEach(board.items) { item in
                if let stack = layout.stack(for: item.id) {
                    stackTile(item, stack: stack)
                } else if let widget = registry.widget(item.widgetID) {
                    let access = FaceWidgetAccess.of(widget, showPersonal: showPersonal, keepsPersonalPlaces: keepsPersonalPlaces)
                    if access != .hidden {
                        let frame = board.grid.frame(for: item.area)
                        let opensApp = opensApps && access == .shown ? widget.opensAppID : nil
                        FaceWidgetTile(widget: widget, size: item.size, isLocked: access == .locked,
                                       settings: layout.settings(for: item.id))
                            .frame(width: frame.width, height: frame.height)
                            .contentShape(RoundedRectangle(cornerRadius: Theme.Radius.tile, style: .continuous))
                            // Off for a widget with no app, whose taps still reach the face.
                            .gesture(TapGesture().onEnded {
                                if let opensApp { services.events.post(.openApp(id: opensApp)) }
                            }, isEnabled: opensApp != nil)
                            .zoomSource(Self.zoomSourceID(item.id), shape: .surface(cornerRadius: Theme.Radius.tile),
                                        isEnabled: opensApps)
                            .offset(x: frame.minX, y: frame.minY)
                            .transition(.opacity)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .nightModeAware()
        .opacity(condition == .night ? Self.nightOpacity : 1)
        // A widget added, moved or resized in the editor settles into place.
        .animation(Theme.Motion.standard, value: board.items)
        // Recognition brings personal widgets in.
        .animation(Theme.Motion.screen, value: showPersonal)
    }

    /// A widget stack, which flips with a vertical swipe on the wall. A tap
    /// opens the app of the widget on top. With none of its widgets to show
    /// its cells stay empty, as a hidden widget's do.
    @ViewBuilder
    private func stackTile(_ item: FaceGridItem, stack: WidgetStack) -> some View {
        let items = FaceStackTile.items(stack, registry: registry, showPersonal: showPersonal,
                                        keepsPersonalPlaces: keepsPersonalPlaces)
        if let first = items.first {
            let frame = board.grid.frame(for: item.area)
            let shownID = services.widgetStacks.shownMemberID(in: item.id.uuidString)
            let shown = items.first { $0.id == shownID } ?? first
            let opensApp = opensApps && shown.isAvailable ? shown.widget.opensAppID : nil
            FaceStackTile(id: item.id, items: items, size: item.size, smartRotate: stack.smartRotate, isInteractive: opensApps)
                .frame(width: frame.width, height: frame.height)
                .contentShape(RoundedRectangle(cornerRadius: Theme.Radius.tile, style: .continuous))
                // Off for a widget with no app, whose taps still reach the face. A swipe is not a tap.
                .gesture(TapGesture().onEnded {
                    if let opensApp { services.events.post(.openApp(id: opensApp)) }
                }, isEnabled: opensApp != nil)
                .zoomSource(Self.zoomSourceID(item.id), shape: .surface(cornerRadius: Theme.Radius.tile),
                            isEnabled: opensApps)
                .offset(x: frame.minX, y: frame.minY)
                .transition(.opacity)
        }
    }

    /// The id a widget on the wall reports itself under (`ZoomSource`), by its placement.
    static func zoomSourceID(_ placement: UUID) -> String { "faceWidget/\(placement.uuidString)" }

    /// How bright widgets are at night, on top of the red tint.
    static let nightOpacity: Double = 0.6
}
