import Foundation
import HomePadCore
import Observation
import SwiftUI

/// Shared state for every face, created once by `FacesModule` and injected
/// into face views by `HostedFace`.
@MainActor
@Observable
final class FacesRuntime {
    let library: FaceLibrary
    let activity: FaceActivityMonitor
    /// Smart Rotation rules, shared by every saved Smart Rotation face.
    let rotation: RotationStore
    /// Vision depth processing with its cache, shared so thumbnails reuse work.
    @ObservationIgnored let photoProcessor = PhotoDepthProcessor()
    /// Pictures of faces for the cards in My Faces, the gallery and the editor.
    @ObservationIgnored let stills = FaceStills()
    /// The size the face on the wall is laid out at (the screen plus the
    /// burn-in margin), reported by the face itself. Thumbnails and the editor
    /// lay faces out at this size so they match the wall exactly: a photo
    /// cropped for another screen shape put the subject in front of the time
    /// in a thumbnail and behind it on the wall.
    var wallCanvas: CGSize?
    /// The face insets on the wall (`\.faceInsets`, with the burn-in overscan),
    /// reported with `wallCanvas`, so a thumbnail laid out at the wall's size
    /// also keeps the wall's margins. The Photos face's time is placed by them.
    var wallInsets: EdgeInsets?
    /// Set by holding the face (`FacesModule.editWallFaceID`): the Faces app
    /// opens the editor on the face on the wall at once, and closing the
    /// editor closes the app, back to the face.
    var editsWallFace = false
    /// The face the wall's pages rest on (`FacePager`), which holding the face edits. It can differ from
    /// the library's current face while something shows another kind (Smart Rotation, a `.showFace`).
    @ObservationIgnored var wallFace: FaceConfiguration?

    init(services: AppServices) {
        library = FaceLibrary(settings: services.settings, household: services.household)
        activity = FaceActivityMonitor()
        rotation = RotationStore(settings: services.settings)
    }

    /// Starts listening for household events. Called from `didFinishLaunching`.
    func start(services: AppServices) {
        activity.start(events: services.events)
    }

    /// A runtime for previews and tests.
    static func preview() -> FacesRuntime {
        FacesRuntime(services: AppServices.preview())
    }
}
