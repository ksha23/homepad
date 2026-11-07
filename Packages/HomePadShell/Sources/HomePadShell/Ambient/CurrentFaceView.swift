import HomePadCore
import HomePadUI
import SwiftUI

/// The face the shell shows right now: a requested face, the active member's
/// choice or the household default (see `FaceResolver`). The ambient screen
/// shows it, and the Home Screen's Face wallpaper frosts it.
///
/// Every kind is built in the same place, with no identity of its own. Kinds
/// that share one view (all of the Faces module's) then stay the same view
/// when the kind changes. A swipe between saved faces ends with the face
/// asking for the kind it landed on, and that must not rebuild the face and
/// its pages.
struct CurrentFaceView: View {
    @Environment(AppServices.self) private var services
    @Environment(ModuleRegistry.self) private var registry
    @Environment(Household.self) private var household
    @Environment(ShellNavigator.self) private var navigator

    var body: some View {
        let faceID = FaceResolver.current(navigator: navigator, household: household, settings: services.settings)
        if let face = faceID.flatMap(registry.face) {
            if face.supportsNightMode {
                face.makeView()
            } else {
                face.makeView().nightModeAware()
            }
        } else {
            BuiltInClockFace()
        }
    }
}
