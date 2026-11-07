import HomePadCore
import HomePadUI
import SwiftUI

/// The Home app, laid out like HomeView's and as compact as Apple Home on iPad:
/// one line of status chips, room picker and Scenes button, a strip of camera
/// snapshots, the favorite scenes if there are any, then accessories by room,
/// each room's sensor readings beside its title and a tile for everything else.
/// One room's page puts its cameras among its tiles instead of in a strip.
/// A tile or a reading opens its full-screen controls and a camera opens full
/// screen, in place, under any overlay such as the doorbell. The Cameras header
/// opens every camera in a grid, and the Scenes button lists every scene.
///
/// It reopens as it was left: on the same room, with the same accessory's
/// controls, camera grid or camera open. A room, accessory or camera that left
/// the home falls back to All Rooms and the home's page. A widget, Control
/// Center, the cameras link and the launch arguments win over all of it.
struct HomeAppView: View {
    @Environment(UnifiedSmartHomeService.self) private var service
    @AppState(SmartHomeAppState.room) private var savedRoom
    @AppState(SmartHomeAppState.accessory) private var detailID
    @AppState(SmartHomeAppState.camera) private var cameraID
    @AppState(SmartHomeAppState.allCameras) private var showsAllCameras
    /// Counted up each time the camera or the accessory's controls close, and part of their identity,
    /// so each opening is a new view. One swiped away still fades out for a moment, and opening
    /// again in that moment brought the closing view back, off the screen and ignoring touches.
    @State private var cameraClosings = 0
    @State private var controlsClosings = 0
    /// Opens straight into one accessory's controls (debug launch argument and deep links).
    var initialDetailID: HomeAccessory.ID?
    /// Opens on one room (debug launch argument).
    var initialRoom: String?
    /// Opens straight into one camera, full screen (debug launch argument).
    var initialCameraID: HomeCamera.ID?

    var body: some View {
        ZStack {
            AppScreen(service.homeName) {
                ScrollView {
                    VStack(alignment: .leading, spacing: Theme.Spacing.l) {
                        BackendStatusBanner(placement: .top).nightModeAware()
                        HomeOverviewRow(selectedRoom: roomSelection).nightModeAware()
                        camerasRow
                        favoriteScenesRow
                        sections
                        BackendStatusBanner(placement: .bottom).nightModeAware()
                    }
                    .padding(.bottom, Theme.Spacing.xl)
                }
                .scrollIndicators(.hidden)
            }
            // Feeds under a camera screen hold a still, so only the cameras in view stream.
            .environment(\.cameraFeedsCovered, showsAllCameras || cameraID != nil || detailID != nil)
            // Each fades in with its page reaching the screen's edges, and only
            // its content zooms (see `FullScreenSurfaceTransition`).
            if showsAllCameras {
                CameraGridScreen(onBack: { showsAllCameras = false }, onOpen: { cameraID = $0 })
                    .environment(\.cameraFeedsCovered, cameraID != nil || detailID != nil)
                    .transition(.fullScreenSurface)
                    .zIndex(1)
            }
            if let cameraID, let camera = service.camera(cameraID) {
                CameraFullScreenView(camera: camera, onShowAll: showAllCameras) {
                    self.cameraID = nil
                    cameraClosings += 1
                }
                .environment(\.cameraFeedsCovered, detailID != nil)
                .id(cameraClosings)
                .transition(.fullScreenSurface)
                .zIndex(2)
            }
            if let detailID {
                AccessoryDetailView(accessoryID: detailID) {
                    self.detailID = nil
                    controlsClosings += 1
                }
                .id(controlsClosings)
                .transition(.fullScreenSurface)
                .zIndex(3)
            }
        }
        .animation(.smooth(duration: 0.3), value: detailID)
        .animation(.smooth(duration: 0.3), value: cameraID)
        .animation(.smooth(duration: 0.3), value: showsAllCameras)
        .accessoryCommandHost()
        .reportsScreenFocus(HomeScreenFocus(accessoryID: detailID, cameraID: cameraID, showsAllCameras: showsAllCameras))
        .onAppear {
            forgetWhatLeftTheHome()
            if let initialDetailID { detailID = initialDetailID }
            if let initialCameraID { cameraID = initialCameraID }
            if let initialRoom { savedRoom = initialRoom }
        }
        .onChange(of: detailID) { old, new in SwipeTrace.trace.log("home controls \(old ?? "none") to \(new ?? "none")") }
        .onChange(of: cameraID) { old, new in SwipeTrace.trace.log("home camera \(old ?? "none") to \(new ?? "none")") }
        // A widget or Control Center asked for an accessory's controls.
        .onChange(of: service.requestedDetailID, initial: true) { _, requested in
            guard let requested else { return }
            detailID = requested
            service.requestedDetailID = nil
        }
        // "cameras" was opened: the camera widget, a face, the doorbell or Siri.
        .onChange(of: service.requestsAllCameras, initial: true) { wasRequested, requested in
            guard requested else { return }
            showsAllCameras = true
            detailID = nil
            // A camera picked at launch stays full screen over the grid. One
            // left open last time gives way to the grid that was asked for.
            cameraID = wasRequested == requested ? initialCameraID : nil
            service.requestsAllCameras = false
        }
        // Home Assistant asked for a camera full screen, or to close it.
        .onChange(of: service.cameraRequest, initial: true) { _, request in
            guard let request else { return }
            switch request {
            case .show(let id):
                detailID = nil
                cameraID = id
            case .close:
                cameraID = nil
            }
            service.cameraRequest = nil
        }
    }

    /// The picked room while the home has it, otherwise All Rooms. The choice
    /// stays saved, so the room comes back if the home loads it later.
    private var selectedRoom: String? {
        guard let savedRoom, service.orderedRooms.contains(savedRoom) else { return nil }
        return savedRoom
    }

    private var roomSelection: Binding<String?> {
        Binding(get: { selectedRoom }, set: { savedRoom = $0 })
    }

    /// An accessory or camera left open that is no longer in the home closes
    /// quietly, rather than opening on "Not Available".
    private func forgetWhatLeftTheHome() {
        if let detailID, !service.allAccessories.contains(where: { $0.id == detailID }) { self.detailID = nil }
        if let cameraID, service.camera(cameraID) == nil { self.cameraID = nil }
    }

    /// Every camera in a strip over All Rooms. A room with nothing but cameras
    /// shows its own, larger, as nothing else needs the room. A room with
    /// accessories puts its cameras at the start of its tiles instead (see
    /// `sections`): its one or two cameras left most of a strip empty.
    @ViewBuilder
    private var camerasRow: some View {
        if let room = selectedRoom {
            let cameras = cameras(in: room)
            // The same test `sections` uses to give the room its tiles.
            if !cameras.isEmpty, !service.accessories.hidingGroupMembers.contains(where: { $0.room == room }) {
                HomeCamerasRow(cameras: cameras, isLarge: true, onShowAll: showAllCameras, onOpen: openCamera)
                    .nightModeAware()
            }
        } else if !service.cameras.isEmpty {
            HomeCamerasRow(cameras: service.cameras, onShowAll: showAllCameras, onOpen: openCamera)
                .nightModeAware()
        }
    }

    private func cameras(in room: String) -> [HomeCamera] {
        service.cameras.filter { $0.room == room }
    }

    private func openCamera(_ id: HomeCamera.ID) {
        cameraID = id
    }

    private func showAllCameras() {
        cameraID = nil
        showsAllCameras = true
    }

    /// Favorite scenes as compact chips over the accessories, on the whole
    /// home's page as in Apple Home. None until the person picks some from the
    /// Scenes button, the Smart Home settings or a chip's menu.
    @ViewBuilder
    private var favoriteScenesRow: some View {
        let scenes = service.favoriteScenes
        if selectedRoom == nil, !scenes.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Theme.Spacing.s) {
                    ForEach(scenes) { scene in
                        SceneButton(scene: scene)
                            .contextMenu {
                                Button("Remove from Favorites", systemImage: "star.slash") {
                                    service.setFavoriteScene(scene.id, isFavorite: false)
                                }
                            }
                    }
                }
            }
            .scrollClipDisabled()
            .nightModeAware()
        }
    }

    @ViewBuilder
    private var sections: some View {
        if service.accessories.isEmpty {
            EmptyStateView("No Accessories", message: "Accessories you add in Apple Home or Home Assistant appear here.", systemImage: "house")
                .frame(minHeight: 320)
        } else {
            // Each Apple Home group stands in for its members. Grouped once per
            // redraw instead of filtering every accessory again for each room.
            let tilesByRoom = Dictionary(grouping: service.accessories.hidingGroupMembers, by: \.room)
            if let room = selectedRoom {
                // Titled even though the picker names the room, so its readings sit
                // beside a name and do not read as more room chips.
                if let accessories = tilesByRoom[room] {
                    HomeRoomSection(title: room, accessories: accessories, cameras: cameras(in: room),
                                    onOpen: open, onOpenCamera: openCamera)
                }
            } else {
                let favorites = service.favorites
                if !favorites.isEmpty {
                    // Favorites mix rooms, so their sensors say which one each is.
                    HomeRoomSection(title: "Favorites", systemImage: "star.fill", accessories: favorites, namesSensors: true, onOpen: open)
                }
                ForEach(service.orderedRooms, id: \.self) { room in
                    // Rooms with only cameras show them in the Cameras row.
                    if let accessories = tilesByRoom[room] { section(title: room, accessories: accessories) }
                }
                if let unassigned = tilesByRoom[nil] {
                    section(title: "Other", accessories: unassigned)
                }
            }
        }
    }

    private func section(title: String, accessories: [HomeAccessory]) -> some View {
        HomeRoomSection(title: title, accessories: accessories, onOpen: open)
    }

    private func open(_ accessoryID: HomeAccessory.ID) {
        detailID = accessoryID
    }
}
