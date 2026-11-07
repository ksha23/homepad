import HomePadCore
import HomePadUI
import SwiftUI

/// `faces.homeModular`: one-tap tiles for favorite accessories, a clock, a
/// camera, Intercom and scenes, on a calm color theme. Lights and fans toggle,
/// the thermostat steps up and down, and locks show their state.
///
/// The editor can choose the accessories and scenes, in order, and the camera.
/// Left empty, the face shows the Home favorites and the first camera.
struct HomeModularFace: View {
    static let style = FaceOption.style([
        FaceChoice("classic", "Clock and Camera", systemImage: "clock"),
        FaceChoice("controls", "Controls Only", systemImage: "square.grid.3x3.fill"),
    ])
    /// The text colors the clock and the tiles that are off. The accent fills the tiles that are on.
    static let color = FaceOption.color([.lavender, .midnight, .sage, .ocean, .coral, .sand, .graphite, .porcelain], default: .lavender,
                                        roles: [.text, .accent, .accentFillsTiles])
    /// The accessories and scenes, in slot order. Slot values are `HomeTile` IDs.
    static let tileSlots = (1...8).map { FaceSlot(id: "tile\($0)", title: "Tile \($0)") }
    static let tiles = FaceOption(
        id: "tiles", title: "Tiles", kind: .slots(tileSlots, .accessoriesAndScenes),
        note: "Leave every tile empty to show your Home favorites."
    )
    static let camera = FaceOption(
        id: "camera", title: "Camera",
        kind: .slots([FaceSlot(id: "camera", title: "Camera", automaticTitle: "Automatic")], .cameras),
        note: "Shows with the Clock and Camera style. Automatic shows the first camera."
    )

    static let definition = FaceDefinition(
        id: "faces.homeModular", title: "Home", summary: "Your favorite accessories, scenes and cameras, one tap away",
        systemImage: "house", sortOrder: 2, options: [style, color, tiles, camera],
        widgets: .besideWidgets()
    ) { HomeModularFace() }

    @Environment(\.faceInsets) private var faceInsets

    @Environment(\.faceConfiguration) private var configuration
    @Environment(\.displayCondition) private var condition
    @Environment(AppServices.self) private var services
    @State private var snapshots = CameraSnapshots()

    var body: some View {
        let palette = FacePalette.resolve(configuration.colors(Self.color), condition: condition)
        let home = services.smartHome
        let isClassic = configuration.value(Self.style) == "classic"
        // The face may have been set up on another HomePad, whose HomeKit IDs differ.
        let cameraID = configuration.slot("camera").map { home.localID(for: $0) }
        let chosen = Self.tileSlots.compactMap { configuration.slot($0.id) }.map { HomeTile.localID($0, in: home) }
        let camera = isClassic ? HomeTile.camera(cameraID, in: home.cameras) : nil
        let tiles = HomeTile.tiles(favorites: home.favorites, cameras: home.cameras, scenes: home.scenes,
                                   includesClockAndCamera: isClassic, accessories: home.accessories,
                                   chosen: chosen, camera: cameraID)
        GeometryReader { proxy in
            // Four tiles across a wide area and four down a tall one, three
            // otherwise, as beside the face's widgets.
            let content = CGSize(width: proxy.size.width - faceInsets.leading - faceInsets.trailing,
                                 height: proxy.size.height - faceInsets.top - faceInsets.bottom)
            let columns = content.width > content.height * 1.25 ? 4 : 3
            let rows = content.height > content.width * 1.25 ? 4 : 3
            let gap = Theme.Spacing.l
            let cell = CGSize(
                width: (content.width - gap * CGFloat(columns - 1)) / CGFloat(columns),
                height: (content.height - gap * CGFloat(rows - 1)) / CGFloat(rows)
            )
            ZStack(alignment: .topLeading) {
                HomeBackdrop(palette: palette)
                ForEach(TileGridPacker.pack(widths: tiles.map(\.width), columns: columns, rows: rows), id: \.index) { spot in
                    HomeTileView(tile: tiles[spot.index], palette: palette, snapshots: snapshots, cellHeight: cell.height)
                        .frame(width: cell.width * CGFloat(spot.width) + gap * CGFloat(spot.width - 1), height: cell.height)
                        // Cameras, Intercom and Home open from their tiles and close back into them.
                        .zoomSource("faceTile/\(tiles[spot.index].id)", shape: .surface(cornerRadius: Theme.Radius.tile))
                        .offset(x: faceInsets.leading + CGFloat(spot.column) * (cell.width + gap),
                                y: faceInsets.top + CGFloat(spot.row) * (cell.height + gap))
                }
            }
        }
        .ignoresSafeArea()
        .task(id: "\(camera?.id ?? "")|\(condition == .sleeping)") {
            // The Smart Home module's shared camera view shows the camera itself.
            // Nothing is fetched while the display sleeps under its black cover.
            guard SmartHomeCameraView.renderer == nil, condition != .sleeping, let camera else { return }
            await snapshots.run(cameras: [camera], service: home, every: 10)
        }
        .faceBackdrop(tone: palette.tone) { HomeBackdrop(palette: palette).ignoresSafeArea() }
        // While the camera tile waits for its first snapshot, when the task above fetches one.
        .faceIsLoading(camera != nil && SmartHomeCameraView.renderer == nil && condition != .sleeping && !snapshots.hasLoaded)
    }
}

/// The theme background: a soft gradient with a few large translucent shapes,
/// in the spirit of HomeView's Home face wallpapers.
private struct HomeBackdrop: View {
    let palette: FacePalette

    var body: some View {
        GeometryReader { proxy in
            let side = max(proxy.size.width, proxy.size.height)
            ZStack {
                Rectangle().fill(palette.background)
                if !palette.isNight {
                    RoundedRectangle(cornerRadius: side * 0.12, style: .continuous)
                        .fill(palette.tile.opacity(0.35))
                        .frame(width: side * 0.7, height: side * 0.22)
                        .rotationEffect(.degrees(-32))
                        .offset(x: -side * 0.2, y: side * 0.05)
                    RoundedRectangle(cornerRadius: side * 0.1, style: .continuous)
                        .fill(Color.white.opacity(palette.isLight ? 0.25 : 0.08))
                        .frame(width: side * 0.6, height: side * 0.16)
                        .rotationEffect(.degrees(-32))
                        .offset(x: side * 0.25, y: side * 0.3)
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .clipped()
        }
    }
}
