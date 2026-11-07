import HomePadCore
import HomePadUI
import SwiftUI

/// Wraps every face this module registers. On the wall it shows the saved
/// faces as pages to swipe between (`FacePager`). In thumbnails, the editor
/// and inside Smart Rotation it draws one face (`HostedFace`): the
/// configuration it is given, or the saved face of its kind. Burn-in drift
/// is the shell's (`AmbientView`), which follows the Burn-In Protection setting.
///
/// The shell shows a face kind by building its registered view, and every
/// kind registers this one view type. So when the shell switches kinds after
/// a swipe, this view and the pager in it stay, with the page on screen.
struct FaceHost: View {
    let definition: FaceDefinition
    let runtime: FacesRuntime
    /// A configuration to draw instead of the saved one (editor previews).
    var configuration: FaceConfiguration?

    @Environment(\.isThumbnail) private var isThumbnail
    @Environment(\.isInsideFaceHost) private var isNested

    var body: some View {
        if isOnWall {
            FacePager(faceID: definition.id, runtime: runtime)
                // Another person's saved faces are another set of pages.
                .id(runtime.library.activeOwner)
                .modifier(DebugLandscape(isEnabled: FaceDebugOptions.forcesLandscape))
        } else {
            HostedFace(definition: definition, runtime: runtime, configuration: resolved, isOnWall: false)
        }
    }

    /// The face on the wall, or its frosted copy behind the Home Screen.
    private var isOnWall: Bool {
        !isNested && !isThumbnail && configuration == nil
    }

    /// The configuration given, else the saved face of this kind. Debug
    /// overrides: the style everywhere, the colors and widgets on a saved
    /// face. The editor applies them to the face it opens, so its preview
    /// still follows the swatches.
    private var resolved: FaceConfiguration {
        let library = runtime.library
        return FaceDebugOptions.withStyleOverride(configuration ?? FaceDebugOptions.withWallOverrides(
            library.configuration(forFace: definition.id, owner: library.activeOwner)))
    }
}

/// Debug only: lays the face out at landscape size and turns it a quarter so
/// a portrait simulator can screenshot the landscape layout.
private struct DebugLandscape: ViewModifier {
    let isEnabled: Bool

    func body(content: Content) -> some View {
        if isEnabled {
            GeometryReader { proxy in
                content
                    .frame(width: proxy.size.height, height: proxy.size.width)
                    .rotationEffect(.degrees(-90))
                    .position(x: proxy.size.width / 2, y: proxy.size.height / 2)
            }
            .ignoresSafeArea()
        } else {
            content
        }
    }
}
