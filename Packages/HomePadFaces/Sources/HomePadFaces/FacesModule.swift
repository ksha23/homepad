import HomePadCore
import HomePadUI
import SwiftUI

/// Always-on faces: photos with the depth effect, clocks, Modular, Home,
/// cameras, weather, calendar, Flow, Night and Critters, plus Smart Rotation,
/// the Faces app ("My Faces" and the face editor) and the Faces settings pane.
public enum FacesModule: HomePadModule {
    public static let id = "faces"
    /// Opens the Faces app straight on the editor for the face on the wall, as holding the face does.
    public static let editWallFaceID = "faces.editWallFace"

    @MainActor private static var runtime: FacesRuntime?

    public static func register(services: AppServices, registry: ModuleRegistry) {
        let runtime = FacesRuntime(services: services)
        Self.runtime = runtime
        for definition in FaceCatalog.all {
            registry.register(face: FaceDescriptor(
                id: definition.id, title: definition.title, systemImage: definition.systemImage,
                sortOrder: definition.sortOrder, supportsNightMode: true
            ) {
                FaceHost(definition: definition, runtime: runtime)
            })
        }
        registry.register(app: AppDescriptor(
            id: "faces", title: "Faces", systemImage: "square.on.square", tint: .indigo,
            category: .system, sortOrder: 70
        ) {
            FacesAppView().environment(runtime)
        })
        registry.register(redirect: AppRedirect(id: editWallFaceID, opens: "faces") {
            runtime.editsWallFace = true
        })
        registry.register(settings: SettingsPaneDescriptor(
            id: "faces", title: "Faces", systemImage: "square.on.square", tint: .cyan, sortOrder: 20
        ) {
            FacesSettingsPane().environment(runtime)
        })
        registry.register(widget: ClockWidget.descriptor)
        FaceSharing.register(runtime: runtime, services: services, in: registry)
    }

    public static func didFinishLaunching(services: AppServices, registry: ModuleRegistry) {
        runtime?.start(services: services)
    }
}
