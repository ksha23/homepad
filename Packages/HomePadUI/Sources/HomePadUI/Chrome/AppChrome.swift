import HomePadCore
import SwiftUI

/// Closes the current full-screen app and returns to the Home Screen. When
/// another app opened it (Music opening Now Playing), `goBack()` returns there.
/// The shell provides it in the environment of every app it hosts.
///
///     @Environment(\.closeApp) private var closeApp
///     Button("Done") { closeApp?() }
///
/// `AppScreen` uses it automatically, so apps built on `AppScreen` get the
/// standard close button, and a back button when there is an app to go back to.
public struct AppCloseAction {
    private let action: @MainActor () -> Void
    private let back: (@MainActor () -> Void)?
    /// The name of the app to go back to, such as "Music". Nil when the app
    /// was opened from the Home Screen.
    public let backTitle: String?

    /// - Parameters:
    ///   - backTitle: The name of the app that opened this one.
    ///   - back: Returns to that app.
    ///   - action: What closing does. The shell passes "go to the Home Screen".
    public init(backTitle: String? = nil, back: (@MainActor () -> Void)? = nil, _ action: @escaping @MainActor () -> Void) {
        self.backTitle = backTitle
        self.back = back
        self.action = action
    }

    @MainActor
    public func callAsFunction() {
        action()
    }

    /// Returns to the app that opened this one, or closes when there is none.
    @MainActor
    public func goBack() {
        (back ?? action)()
    }
}

public extension EnvironmentValues {
    /// Set by the shell for the app it is showing. Nil outside an app (faces, widgets, previews).
    @Entry var closeApp: AppCloseAction?
    /// Whether apps show the close button top right. The shell turns it off
    /// unless Show Close Buttons is on, since a swipe up from the bottom edge
    /// closes any app. Sheets, details and overlays keep theirs.
    @Entry var showsAppCloseButton = true
}

/// True when a screen draws its own close button, so the shell does not add a second one.
/// `AppScreen` sets it. Custom app chrome can set it too:
///
///     .preference(key: AppDrawsCloseButtonKey.self, value: true)
public struct AppDrawsCloseButtonKey: PreferenceKey {
    public static let defaultValue = false
    public static func reduce(value: inout Bool, nextValue: () -> Bool) {
        value = value || nextValue()
    }
}

public extension View {
    /// Gives a full-screen cover the room every other screen has around it.
    /// UIKit presents a cover above the shell's root view controller, so the
    /// margin the shell adds to the window's safe area does not reach it, and
    /// its close button would sit closer to the bezel than on every other
    /// screen. Apply it to the cover's content, and keep backgrounds full bleed
    /// with `ignoresSafeArea()`.
    ///
    ///     .fullScreenCover(isPresented: $isScanning) { RoomScanScreen().coverScreenMargin() }
    func coverScreenMargin() -> some View {
        safeAreaPadding(Theme.Spacing.screenMargin)
    }

    /// Keeps the display active (no dimming, no return to the face) while this
    /// view is on screen. Use for hands-busy screens such as cooking mode.
    ///
    ///     CookingModeView().keepsDisplayActive("kitchen.cooking")
    func keepsDisplayActive(_ owner: String) -> some View {
        modifier(KeepsDisplayActiveModifier(owner: owner))
    }
}

private struct KeepsDisplayActiveModifier: ViewModifier {
    let owner: String
    @Environment(AppServices.self) private var services

    func body(content: Content) -> some View {
        content
            .onAppear { services.holdDisplayActive(owner) }
            .onDisappear { services.releaseDisplayActive(owner) }
    }
}
