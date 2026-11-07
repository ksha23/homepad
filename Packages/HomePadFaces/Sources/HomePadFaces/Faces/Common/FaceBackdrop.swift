import HomePadCore
import HomePadUI
import SwiftUI

/// Behind the Home Screen a face is only a backdrop. The shell keeps a copy of
/// the face there, blurred, and tells it so with `\.isFrosted`. Like HomeView's
/// Home Screen, that copy shows the face's picture or background alone: no
/// time, date, temperature, text, dial, tiles or widgets.
///
/// Faces mark what goes with one of two modifiers:
///
/// - `faceBackdrop(_:)` for a face whose background is a still color or
///   gradient (Modular, Home, Calendar, the clocks, Night). Behind the Home
///   Screen the backdrop is all that draws, so the face's timeline and its
///   data tasks (events, camera snapshots) do not run there.
/// - `faceForeground()` for the parts drawn over a picture that the face
///   itself keeps changing (the time over a photo or a sky, Flow's drops,
///   the words beside Sprig). The picture goes on drawing, and only these
///   parts leave.
///
/// Both leave the background in place while the rest fades with the Home
/// Screen, so the face's colors never dip as the Home Screen comes and goes.
///
/// Every face also reports how bright its backdrop is (`backdropTone(_:)`,
/// from HomePadUI), so glass widgets on the face and on the Home Screen over
/// its frosted copy are dark over a dark face and light over a bright one.
/// `faceBackdrop(tone:_:)` reports the tone it is given. A face drawn over
/// a picture reports its own from the picture's colors.
/// The editor, My Faces and the face on the wall are not frosted, so they
/// draw everything.
extension View {
    /// Draws `backdrop` under the face, and alone behind the Home Screen. The
    /// face keeps drawing its own background too, so its layout never depends
    /// on this, and the backdrop under it keeps the background steady while
    /// the rest fades in and out with the Home Screen.
    ///
    /// - Parameter tone: How bright the backdrop is, usually the palette's
    ///   (`FacePalette.tone`), reported for glass laid over the face.
    func faceBackdrop<Backdrop: View>(tone: BackdropTone, @ViewBuilder _ backdrop: () -> Backdrop) -> some View {
        modifier(FaceBackdropModifier(backdrop: backdrop(), tone: tone))
    }

    /// Leaves the view out behind the Home Screen, where a face shows only its
    /// picture or background. Nothing inside it runs there: no timeline, task
    /// or layout.
    func faceForeground() -> some View {
        modifier(FaceForegroundModifier())
    }
}

private struct FaceForegroundModifier: ViewModifier {
    @Environment(\.isFrosted) private var isFrosted

    func body(content: Content) -> some View {
        if !isFrosted {
            content
        }
    }
}

private struct FaceBackdropModifier<Backdrop: View>: ViewModifier {
    let backdrop: Backdrop
    let tone: BackdropTone

    func body(content: Content) -> some View {
        ZStack(alignment: .topLeading) {
            backdrop
            content.faceForeground()
        }
        .backdropTone(tone)
    }
}
