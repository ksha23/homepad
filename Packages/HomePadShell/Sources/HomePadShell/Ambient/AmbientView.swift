import HomePadCore
import HomePadUI
import SwiftUI

/// The always-on face. Tap goes to the Home Screen, and a hold opens the editor
/// for the face on screen (inside the Faces app), and closing it comes back
/// here. Swipe between saved faces to pick another. A
/// horizontal swipe pages between the saved faces, which the face does itself
/// (the Faces module's pager), so the profile dot and pills stay put while the
/// faces move. Burn-in protection drifts the face a few points, laid out with
/// just enough overscan that no black edge shows.
///
/// Every face shows the Home Screen's avatar in its top right corner, the same
/// size and in the same spot, so a glance says whether anyone is recognized
/// (and whose calendar shows) without the face drawing a hint of its own, and
/// the avatar stays put going to the Home Screen. Faces keep clear of it
/// (`FaceWidgetSupport.profileZone`).
///
/// While a timer runs or music plays the face shows the timer and Now Playing
/// pills at the top center (`TopPills`), small from across the room and larger
/// up close, and the face's top inset grows to make room for them, so they
/// never cover the time.
struct AmbientView: View {
    @Environment(AppServices.self) private var services
    @Environment(ModuleRegistry.self) private var registry
    @Environment(ShellNavigator.self) private var navigator
    @Environment(KioskController.self) private var kiosk
    @Environment(Household.self) private var household
    @Environment(\.isFrosted) private var isFrosted
    @Environment(\.proximity) private var proximity

    var body: some View {
        GeometryReader { proxy in
            // Lay the face out larger than the screen by the largest drift on every
            // side, so shifting it never uncovers a black edge.
            let overscan = burnInOverscan
            let insets = Theme.Spacing.screenContent
            // The face's content moves down while a pill shows. Its widgets keep
            // their place and keep clear of the pills (`\.faceNowPlayingRoom`).
            let pillRoom = showsPills ? Theme.Size.faceNowPlayingRoom : 0
            CurrentFaceView()
                .environment(\.faceInsets, EdgeInsets(top: insets.top + overscan + pillRoom, leading: insets.leading + overscan,
                                                       bottom: insets.bottom + overscan, trailing: insets.trailing + overscan))
                .environment(\.faceNowPlayingRoom, pillRoom)
                .frame(width: proxy.size.width + 2 * overscan, height: proxy.size.height + 2 * overscan)
                .overlay(alignment: .topTrailing) {
                    // Where the Home Screen's header has it, as far from the top as
                    // from the side, and drifting with the face.
                    if showsProfileDot {
                        ProfileDot(
                            member: household.isPersonalContentUnlocked ? household.activeMember : nil,
                            isRecognitionStarting: services.presence.isRecognitionStarting
                        )
                            .padding(.top, overscan + Theme.Size.profileButtonInset)
                            .padding(.trailing, overscan + Theme.Size.profileButtonInset)
                            .transition(.opacity)
                    }
                }
                .overlay(alignment: .top) {
                    // In the shell's top margin, drifting with the face. Red at night
                    // like the face. Each pill moves in and out on its own.
                    if mayShowPills {
                        TopPills(isCompact: proximity < .mid)
                            .nightModeAware()
                            .padding(.top, overscan + Theme.Spacing.screenMargin.top)
                    }
                }
                // The face makes room as a pill comes in, and takes it back as the last goes.
                .animation(Theme.Motion.settle, value: showsPills)
                .offset(x: kiosk.burnInOffset.width - overscan, y: kiosk.burnInOffset.height - overscan)
                .animation(Theme.Motion.ambient, value: kiosk.burnInOffset)
        }
        .ignoresSafeArea()
        .contentShape(Rectangle())
        .onTapGesture { navigator.goHome() }
        // Hold anywhere to customize the face. Taps, the face's buttons and its swipe
        // keep working (see `ChooseFaceGesture`).
        .gesture(ChooseFaceGesture(isEnabled: canChooseFace, perform: chooseFace))
        .accessibilityAction(named: "Show Home Screen") { navigator.goHome() }
        .accessibilityAction(named: "Customize Face") { chooseFace() }
    }

    /// The Faces app is there to open. Without it (no Faces module) a hold does nothing.
    private var canChooseFace: Bool {
        registry.app(KnownAppID.faces) != nil
    }

    /// Opens the editor for the face on the wall, inside Faces. Closing the editor goes back to the face.
    /// Without the editor's redirect it opens My Faces.
    private func chooseFace() {
        guard canChooseFace else { return }
        let editor = registry.redirect(KnownAppID.editWallFace) != nil
        // A fade, not the app zoom: the whole face was held, so there is no part of it to grow out of.
        navigator.open(appID: editor ? KnownAppID.editWallFace : KnownAppID.faces, fromFace: true, fades: true)
    }

    /// Points of extra face on each side, enough to cover the largest drift.
    private var burnInOverscan: CGFloat {
        CGFloat(max(0, services.settings[ShellSettings.burnInAmplitude]))
    }

    /// The face is the screen. Under the Home Screen's frost the header shows
    /// the pills, and a sleeping display shows nothing.
    private var mayShowPills: Bool {
        !isFrosted && kiosk.condition != .sleeping
    }

    /// A timer runs or music plays while the face is the screen.
    private var showsPills: Bool {
        mayShowPills && !TopPillsContent(services: services).isEmpty
    }

    /// Not under the Home Screen's frost, whose header shows the avatar itself,
    /// and not before anyone is set up, when there is nobody to recognize.
    private var showsProfileDot: Bool {
        !isFrosted && !household.members.isEmpty
    }
}

/// Who the face is showing for: the recognized member's avatar, or the
/// guest glyph while nobody is recognized. The Home Screen header's avatar,
/// on the same glass, so it reads as the same button. A tap goes through to
/// the face, which goes to the Home Screen.
private struct ProfileDot: View {
    let member: HouseholdMember?
    /// Face recognition is still loading after launch: a turning ring, as on the header's avatar.
    let isRecognitionStarting: Bool

    var body: some View {
        AvatarView(member: member, size: Theme.Size.profileButton)
            .startingRing(isRecognitionStarting)
            .glassEffect(.regular, in: Circle())
            .nightModeAware()
            .allowsHitTesting(false)
            .accessibilityLabel(isRecognitionStarting ? "Face recognition is starting"
                : member.map { "\($0.name) recognized" } ?? "Nobody recognized")
    }
}
