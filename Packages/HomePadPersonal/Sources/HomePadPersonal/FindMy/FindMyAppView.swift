import HomePadCore
import HomePadUI
import MapKit
import SwiftUI

/// Find My: a live map of the household's phones, iPads and watches from Home
/// Assistant, under a glass panel that lists them like Apple's Devices tab.
/// Tapping a device in the list or on the map centers the map on it and opens
/// its card with its address and Play Sound.
///
/// The map fills the screen behind the standard header. The panel sits on the
/// leading side in landscape and across the bottom in portrait, and the map
/// frames its pins in the part the panel leaves free.
///
/// It reopens on each person's selected device while they may still see it,
/// and otherwise where they left the map in this launch.
struct FindMyAppView: View {
    @Environment(FindMyService.self) private var findMy
    @AppState(PersonalAppState.findMyDevice) private var selection
    @AppState(PersonalAppState.findMyRegion) private var savedRegion
    @State private var position = MapCameraPosition.automatic
    @State private var layout = FindMyLayoutFrames()

    var body: some View {
        let isReady = findMy.setup == .ready
        ZStack {
            if isReady {
                FindMyMapView(devices: findMy.visibleDevices, zones: findMy.zones, selection: $selection, position: $position,
                              onSettle: saveRegion)
                    .safeAreaPadding(layout.mapInsets)
                    .ignoresSafeArea()
                    .onGeometryChange(for: CGRect.self) { $0.frame(in: .named(FindMyLayoutFrames.space)) } action: { layout.map = $0 }
                headerShade
            }
            AppScreen("Find My", accessory: { OpenFindMyButton() }) {
                if isReady {
                    FindMyPanelLayout(measured: $layout) { panel }
                } else {
                    FindMySetupView(setup: findMy.setup, viewerName: findMy.recognizedMember?.name)
                }
            }
        }
        .coordinateSpace(.named(FindMyLayoutFrames.space))
        .nightModeAware()
        .onChange(of: selection) { focus() }
        .onChange(of: selectedSpot) { if selection != nil { focus() } }
        .onChange(of: findMy.device(selection) == nil) { _, isGone in
            if isGone { selection = nil }
        }
        .onAppear {
            applyLaunchSelection()
            if findMy.device(selection) == nil, let savedRegion {
                position = .region(savedRegion.region)
            } else {
                focus(animated: false)
            }
        }
    }

    private var panel: some View {
        Group {
            if let device = findMy.device(selection) {
                FindMyDeviceCard(device: device) { selection = nil }
                    .transition(.opacity)
            } else {
                FindMyDeviceList(devices: findMy.visibleDevices, viewerID: findMy.recognizedMember?.id, selection: $selection)
                    .transition(.opacity)
            }
        }
        .animation(Theme.Motion.standard, value: selection)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: Theme.Radius.tile, style: .continuous))
    }

    /// A shade of the page color at the top, so the title and the glass buttons
    /// read over the map: dark over the dark map, light over the light one.
    private var headerShade: some View {
        LinearGradient(colors: [Color.screenBackground.opacity(0.45), .clear], startPoint: .top, endPoint: .bottom)
            .frame(height: 200)
            .frame(maxHeight: .infinity, alignment: .top)
            .ignoresSafeArea()
            .allowsHitTesting(false)
    }

    /// Where the selected device is, so the map follows it when Home Assistant moves it.
    private var selectedSpot: String? {
        guard let tracked = findMy.device(selection)?.tracked, let latitude = tracked.latitude,
              let longitude = tracked.longitude else { return nil }
        return FindMyAddressBook.key(latitude, longitude)
    }

    /// Centers on the selected device, or shows every device when none is selected.
    private func focus(animated: Bool = true) {
        let target = findMy.device(selection).flatMap { FindMyCamera.focus(on: $0.tracked) }
            ?? FindMyCamera.overview(devices: findMy.visibleDevices, zones: findMy.zones)
        withAnimation(animated ? Theme.Motion.screen : nil) { position = target }
    }

    /// Where the map came to rest with no device selected. A selected device
    /// is restored by its selection instead, since the map follows it.
    private func saveRegion(_ region: MKCoordinateRegion) {
        if selection == nil { savedRegion = FindMyMapRegion(region) }
    }

    /// `-HomePadFindMyDevice "Sam's iPhone"` opens on that device's card (debug
    /// builds), over the device Find My was left on.
    private func applyLaunchSelection() {
        guard let wanted = PersonalDebugLaunch.findMyDevice, let device = findMy.visibleDevices.first(where: {
            $0.id == wanted || $0.title.localizedCaseInsensitiveCompare(wanted) == .orderedSame
        }) else { return }
        selection = device.id
    }
}
