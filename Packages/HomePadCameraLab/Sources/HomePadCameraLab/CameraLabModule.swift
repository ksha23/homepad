import HomePadCore
import HomePadUI
import SwiftUI

/// Back-camera features HomeView does not have: Ask About This, recipe and
/// document scanning, grocery barcodes, a LAN security camera, LiDAR floor
/// plans, timelapse and a QR scanner.
///
/// Debug launch arguments:
///   -CameraLabTool <ask|documents|groceries|security|floorPlan|timelapse|qr>   open a tool
///   -CameraLabSecurity on                                                    turn Security Camera on at launch
///   -CameraLabDemoFlyer YES                                                  with -CameraLabTool documents, read a sample
///                                                                            invitation and open the event review
public enum CameraLabModule: HomePadModule {
    public static let id = "cameralab"
    /// The hub app.
    public static let appID = "cameralab"
    /// The Floor Plan app.
    public static let floorPlanAppID = "floorplan"
    /// The settings pane.
    public static let settingsPaneID = "cameralab"

    /// Kept between `register` and `didFinishLaunching`.
    private static var lab: CameraLab?

    public static func register(services: AppServices, registry: ModuleRegistry) {
        let lab = CameraLab(services: services)
        self.lab = lab

        registry.register(app: AppDescriptor(
            id: appID, title: "Camera Lab", systemImage: "camera.aperture", tint: .orange,
            category: .camera, sortOrder: 60
        ) {
            CameraLabHubView().environment(lab)
        })
        registry.register(app: AppDescriptor(
            id: floorPlanAppID, title: "Floor Plan", systemImage: "square.split.bottomrightquarter", tint: .teal,
            category: .home, sortOrder: 20
        ) {
            FloorPlanAppView().environment(lab)
        })
        registry.register(settings: SettingsPaneDescriptor(
            id: settingsPaneID, title: "Camera Lab", systemImage: "camera.aperture", tint: .purple, sortOrder: 70
        ) {
            CameraLabSettingsPane().environment(lab)
        })
        registry.register(tools: CameraLabTools.make(lab: lab))
        registry.register(overlay: OverlayDescriptor(id: "cameralab.securityIndicator", zIndex: 40) {
            SecurityIndicatorOverlay().environment(lab)
        })
        registry.register(control: ControlDescriptor(id: "cameralab.security", title: "Security Camera", sortOrder: 80) {
            SecurityControlTile().environment(lab)
        })
    }

    public static func didFinishLaunching(services: AppServices, registry: ModuleRegistry) {
        guard let lab else { return }
        if UserDefaults.standard.string(forKey: "CameraLabSecurity") == "on" {
            lab.security.setEnabled(true)
        } else {
            lab.security.restoreIfNeeded()
        }
        lab.timelapse.restoreIfNeeded()
    }
}
