import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// What the home bar does, from the shell. A tap goes Home. A drag up moves the app's window with the
/// finger, then goes Home or springs back. The shell hands it to every app it hosts as `\.homeBar`, so a
/// full-screen cover the app presents draws the same bar with the same actions (`coverHomeBar()`).
public struct HomeBarActions {
    /// A tap: goes Home, or back to the face when the face opened the app.
    public var goHome: @MainActor () -> Void
    /// The finger has moved this far since the drag began. The window follows it.
    public var track: @MainActor (_ translation: CGSize) -> Void
    /// The finger lifted, with the drag's predicted end and its speed in points per second. Goes Home when
    /// the drag was far or fast enough, otherwise springs back.
    public var finish: @MainActor (_ translation: CGSize, _ predicted: CGSize, _ velocity: CGSize) -> Void
    /// The drag ended without the finger lifting, as when the system takes the touch. Springs back.
    public var settle: @MainActor () -> Void

    public init(goHome: @escaping @MainActor () -> Void,
                track: @escaping @MainActor (_ translation: CGSize) -> Void,
                finish: @escaping @MainActor (_ translation: CGSize, _ predicted: CGSize, _ velocity: CGSize) -> Void,
                settle: @escaping @MainActor () -> Void) {
        self.goHome = goHome
        self.track = track
        self.finish = finish
        self.settle = settle
    }
}

public extension EnvironmentValues {
    /// The home bar's actions, set by the shell for the app it is showing. Nil outside an app, so a cover
    /// the shell presents itself (onboarding) draws no bar.
    @Entry var homeBar: HomeBarActions?
}

/// The home bar at the bottom of an open app, where the iPadOS home indicator sits. Tap it to go Home.
/// Drag it up and the app's window follows the finger, then goes Home or springs back. Only a strip at
/// the very bottom takes touches, so the app above is never covered. The shell draws it over every app,
/// and `coverHomeBar()` draws it over an app's full-screen covers.
public struct HomeBar: View {
    private let actions: HomeBarActions
    /// True while a finger is on the bar. It also resets when the touch is cancelled, which `onEnded` never hears.
    @GestureState private var isTouching = false
    /// True once the finger has moved far enough to drag the window. Until then the touch is a tap.
    @State private var isSwiping = false

    private let pill = CGSize(width: 280, height: 6)
    private let hitSize = CGSize(width: 360, height: 34)
    /// How far the finger moves before the touch drags the window rather than taps.
    private let swipeDistance: CGFloat = 4

    public init(actions: HomeBarActions) {
        self.actions = actions
    }

    public var body: some View {
        GeometryReader { _ in
            // The window's inset, which the keyboard never shrinks. The pill is
            // centered in that band at the very bottom of the screen.
            let inset = Self.windowBottomInset()
            let restingGap = max(4, (inset - pill.height) / 2)
            VStack(spacing: 0) {
                Spacer(minLength: 0).allowsHitTesting(false)
                Color.clear
                    .frame(width: hitSize.width, height: hitSize.height)
                    .contentShape(Rectangle())
                    .overlay(alignment: .bottom) {
                        Capsule()
                            .fill(.primary.opacity(0.45))
                            .frame(width: pill.width, height: pill.height)
                            .offset(y: -restingGap)
                    }
                    .gesture(touch)
                    .accessibilityElement()
                    .accessibilityLabel("Home")
                    .accessibilityAddTraits(.isButton)
                    .accessibilityIdentifier("home-bar")
                    .accessibilityAction { actions.goHome() }
            }
            .frame(maxWidth: .infinity)
        }
        .ignoresSafeArea()
        .onChange(of: isTouching) { _, touching in
            guard !touching else { return }
            isSwiping = false
            actions.settle()
        }
    }

    /// The tap and the swipe as one gesture, so they never race. With a tap and a drag of their own, the
    /// drag waited for the tap to fail, and a slow pull sometimes ended as a tap that went Home instead of
    /// springing back. Global coordinates, because the bar moves under the finger.
    private var touch: some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .global)
            .updating($isTouching) { _, touching, _ in touching = true }
            .onChanged { value in
                if !isSwiping, hypot(value.translation.width, value.translation.height) >= swipeDistance {
                    isSwiping = true
                }
                if isSwiping { actions.track(value.translation) }
            }
            .onEnded { value in
                if isSwiping {
                    actions.finish(value.translation, value.predictedEndTranslation, value.velocity)
                } else {
                    actions.goHome()
                }
                isSwiping = false
            }
    }

    /// The bottom safe area of the key window, 0 where there is none.
    static func windowBottomInset() -> CGFloat {
        #if canImport(UIKit)
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let window = scenes.flatMap(\.windows).first(where: \.isKeyWindow) ?? scenes.first?.windows.first
        return window?.safeAreaInsets.bottom ?? 0
        #else
        return 0
        #endif
    }
}

public extension View {
    /// Draws the app's home bar over a full-screen cover, so a tap or a swipe up from the bottom edge goes
    /// Home from the cover as from the app under it. The cover's window follows the finger and shrinks into
    /// the app's icon, and a short swipe springs back to the cover. UIKit presents a cover above the shell,
    /// so the bar the shell draws over the app never reaches it. Apply it to the content of every
    /// `fullScreenCover` an app presents. Outside an app (`\.homeBar` is nil) it draws nothing.
    ///
    ///     .fullScreenCover(isPresented: $isScanning) { RoomScanScreen().coverScreenMargin().coverHomeBar() }
    ///
    /// - Parameter colorScheme: The look of a cover whose page keeps one color in every appearance, such as
    ///   `.dark` for a black photo viewer, so the bar reads on it. Nil follows the appearance.
    func coverHomeBar(colorScheme: ColorScheme? = nil) -> some View {
        modifier(CoverHomeBar(colorScheme: colorScheme))
    }
}

private struct CoverHomeBar: ViewModifier {
    let colorScheme: ColorScheme?
    @Environment(\.homeBar) private var homeBar
    @Environment(\.colorScheme) private var appearance

    func body(content: Content) -> some View {
        content
            .overlay {
                if let homeBar {
                    HomeBar(actions: homeBar)
                        .environment(\.colorScheme, colorScheme ?? appearance)
                }
            }
            // A cover is its own presentation, so it asks for what the shell's root asks for: the first
            // swipe from the bottom edge stays with the bar, and the system's home indicator stays hidden.
            #if os(iOS)
            .defersSystemGestures(on: .vertical)
            #endif
            .persistentSystemOverlays(.hidden)
    }
}
