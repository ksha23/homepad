import HomePadCore
import HomePadUI
import SwiftUI

/// `faces.cameras`: up to nine camera snapshots, refreshed every few seconds.
/// A camera whose doorbell just rang moves to the front and gets a ring.
/// Tap any feed to open the Cameras app.
///
/// From across the room the pictures are all there is: the grid runs almost
/// to the screen's edges, keeping only the burn-in overscan and the room
/// kept clear for widgets and the Now Playing pill, with thin dividers and no
/// labels, like HomeView's. Up close it moves in to the face insets, with
/// rounded feeds, their names and times.
///
/// Feeds go live only up close on the face itself. Behind the Home Screen
/// the face keeps its far look, the pictures alone, refreshed slowly. While
/// the display sleeps under its black cover the face draws no feeds at all,
/// so nine cameras are not fetched all night.
///
/// The editor can choose the cameras and their order. Left empty, the face
/// shows the home's first nine.
struct CamerasFace: View {
    static let maxFeeds = 9

    static let style = FaceOption.style([
        FaceChoice("grid", "Grid", systemImage: "square.grid.3x3"),
        FaceChoice("focus", "Focus", systemImage: "rectangle.grid.1x2"),
    ])
    static let cameraSlots = (1...maxFeeds).map { FaceSlot(id: "camera\($0)", title: "Camera \($0)") }
    static let cameras = FaceOption(
        id: "cameras", title: "Cameras", kind: .slots(cameraSlots, .cameras),
        note: "Leave every camera empty to show the first nine in the Home app."
    )

    static let definition = FaceDefinition(
        id: "faces.cameras", title: "Cameras", summary: "Up to nine camera feeds at once",
        systemImage: "video", sortOrder: 3, options: [style, cameras],
        widgets: .besideWidgets()
    ) { CamerasFace() }

    @Environment(\.faceInsets) private var faceInsets
    @Environment(\.faceProfileZone) private var profileZone

    @Environment(\.faceConfiguration) private var configuration
    @Environment(\.proximity) private var proximity
    @Environment(\.isThumbnail) private var isThumbnail
    @Environment(\.isFrosted) private var isFrosted
    @Environment(\.displayCondition) private var condition
    @Environment(AppServices.self) private var services
    @Environment(FacesRuntime.self) private var runtime
    @State private var snapshots = CameraSnapshots()

    var body: some View {
        let cameras = orderedCameras
        Group {
            if cameras.isEmpty {
                EmptyStateView("No Cameras", message: "Cameras you add in the Home app appear here.", systemImage: "video.slash")
                    .faceForeground()
            } else if condition == .sleeping {
                Color.black
            } else {
                GeometryReader { face in
                    // Clear of the profile button in the corner at both distances.
                    let insets = (isNear ? faceInsets : Self.farInsets(faceInsets)).clearing(profileZone, in: face.size)
                    GeometryReader { proxy in
                        layout(cameras, in: proxy.size)
                    }
                    // The corners of the grid follow the feeds' up close, so from
                    // across the room only the outer ones are round.
                    .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.tile, style: .continuous))
                    .padding(insets)
                }
            }
        }
        .background(Color.black.ignoresSafeArea())
        // Feeds on black with dark dividers, so glass over them is dark.
        .backdropTone(.black)
        .task(id: PollKey(cameras: cameras.map(\.id), interval: pollInterval)) {
            // The Smart Home module's shared camera view streams on its own.
            guard SmartHomeCameraView.renderer == nil, let interval = pollInterval else { return }
            await snapshots.run(cameras: cameras, service: services.smartHome, every: interval)
        }
        // While the feeds wait for their first snapshots, when the task above fetches them.
        .faceIsLoading(!cameras.isEmpty && condition != .sleeping && SmartHomeCameraView.renderer == nil
                       && pollInterval != nil && !snapshots.hasLoaded)
    }

    /// The near look: rounded feeds inside the face insets, with live video,
    /// names and times. Behind the Home Screen the face keeps its far look,
    /// the pictures alone.
    private var isNear: Bool {
        proximity >= .mid && !isFrosted
    }

    /// The gap between feeds from across the room: a thin divider.
    static let farDivider: CGFloat = 2

    /// The grid's insets from across the room: the face insets less the
    /// shell's margin, which leaves the burn-in overscan and the room kept
    /// clear for widgets and the Now Playing pill, and a thin edge.
    static func farInsets(_ faceInsets: EdgeInsets) -> EdgeInsets {
        let margin = Theme.Spacing.screenContent
        func edge(_ inset: CGFloat, less base: CGFloat) -> CGFloat {
            max(inset - base, 0) + Theme.Spacing.xs
        }
        return EdgeInsets(top: edge(faceInsets.top, less: margin.top),
                          leading: edge(faceInsets.leading, less: margin.leading),
                          bottom: edge(faceInsets.bottom, less: margin.bottom),
                          trailing: edge(faceInsets.trailing, less: margin.trailing))
    }

    /// Seconds between snapshots, or nil while the display sleeps.
    private var pollInterval: TimeInterval? {
        if isThumbnail { return 3600 }
        if condition == .sleeping { return nil }
        return isFrosted ? 30 : 4
    }

    private struct PollKey: Hashable {
        var cameras: [HomeCamera.ID]
        var interval: TimeInterval?
    }

    /// Cameras in display order: a doorbell that rang in the last two minutes first.
    private var orderedCameras: [HomeCamera] {
        let home = services.smartHome
        let chosen = Self.chosenCameras(configuration, available: home.cameras) { home.localID(for: $0) }
        return Self.ordered(chosen, ringing: ringingCameraID)
    }

    /// The cameras in the face's slots, in slot order and each once, skipping
    /// cameras that no longer exist. With none chosen, or none of them left,
    /// the home's first nine. `localID` reads a camera picked on another
    /// HomePad as this one knows it.
    static func chosenCameras(_ configuration: FaceConfiguration, available: [HomeCamera],
                              localID: (String) -> String = { $0 }) -> [HomeCamera] {
        var seen = Set<String>()
        let picked = cameraSlots.compactMap { slot -> HomeCamera? in
            guard let id = configuration.slot(slot.id).map(localID), seen.insert(id).inserted else { return nil }
            return available.first { $0.id == id }
        }
        return Array((picked.isEmpty ? available : picked).prefix(maxFeeds))
    }

    /// Moves the camera whose doorbell just rang to the front.
    static func ordered(_ cameras: [HomeCamera], ringing: String?) -> [HomeCamera] {
        var cameras = cameras
        if let ringing, let index = cameras.firstIndex(where: { $0.id == ringing }) {
            cameras.insert(cameras.remove(at: index), at: 0)
        }
        return cameras
    }

    private var ringingCameraID: String? {
        runtime.activity.happened(.doorbell, within: 120) ? runtime.activity.lastDoorbellCameraID : nil
    }

    @ViewBuilder
    private func layout(_ cameras: [HomeCamera], in size: CGSize) -> some View {
        let gap = isNear ? Theme.Spacing.s : Self.farDivider
        if configuration.value(Self.style) == "focus", cameras.count > 1 {
            let isPortrait = size.height > size.width
            let others = Array(cameras.dropFirst().prefix(4))
            let stack = isPortrait ? AnyLayout(HStackLayout(spacing: gap)) : AnyLayout(VStackLayout(spacing: gap))
            let outer = isPortrait ? AnyLayout(VStackLayout(spacing: gap)) : AnyLayout(HStackLayout(spacing: gap))
            outer {
                feed(cameras[0]).layoutPriority(1)
                    .frame(width: isPortrait ? nil : size.width * 0.7, height: isPortrait ? size.height * 0.7 : nil)
                stack {
                    ForEach(others) { feed($0) }
                }
            }
        } else {
            let grid = GridMath.dimensions(count: cameras.count, in: size, cellAspect: 16 / 9)
            let cellHeight = (size.height - gap * CGFloat(grid.rows - 1)) / CGFloat(grid.rows)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: gap), count: grid.columns), spacing: gap) {
                ForEach(cameras) { feed($0).frame(height: cellHeight) }
            }
        }
    }

    private func feed(_ camera: HomeCamera) -> some View {
        CameraFeedTile(
            camera: camera, image: snapshots.images[camera.id], updatedAt: snapshots.updatedAt[camera.id],
            isPlaceholder: snapshots.placeholders.contains(camera.id), isRinging: camera.id == ringingCameraID,
            isNear: isNear
        )
        .contentShape(Rectangle())
        .onTapGesture { services.events.post(.openApp(id: "cameras")) }
        // Cameras closes back into the feed it was opened from.
        .zoomSource("faceCamera/\(camera.id)", shape: .surface(cornerRadius: isNear ? Theme.Radius.tile : 0))
    }
}
