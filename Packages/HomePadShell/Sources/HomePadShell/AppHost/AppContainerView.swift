import HomePadCore
import HomePadUI
import SwiftUI

/// Hosts one app full screen. It gives the app a `\.closeApp` action, its
/// `\.appAccent` (the icon's tint) and the home bar's actions (`\.homeBar`, for
/// the bar over the covers it presents), and adds the standard close button
/// unless the app draws its own (as `AppScreen` does) or close buttons are off.
/// The shell draws the home bar above it all (`HomeBar`).
struct AppContainerView: View {
    let appID: String
    /// True when the app that opened this one is kept alive underneath.
    var hasAppBehind = false
    /// Told when a swipe down starts pulling the app aside and when it settles.
    var onPull: (Bool) -> Void = { _ in }
    @Environment(ModuleRegistry.self) private var registry
    @Environment(ShellNavigator.self) private var navigator
    @Environment(\.showsAppCloseButton) private var showsAppCloseButton
    @State private var appDrawsCloseButton = false
    @State private var isPulled = false

    var body: some View {
        ZStack(alignment: .topTrailing) {
            // The page color of the app's appearance. Clear while the app is
            // pulled down, so the app underneath shows through the fading
            // backdrop the swipe draws instead.
            Color.screenBackground
                .opacity(hasAppBehind && isPulled ? 0 : 1)
                .ignoresSafeArea()
            if let app = registry.app(appID) {
                app.makeView()
                    // The app's own color, the tint of its icon, so a header's
                    // prominent action matches the app without a call of its own.
                    .appAccent(app.tint)
                    .environment(\.closeApp, closeAction)
                    .environment(\.homeBar, navigator.homeBarActions)
                    .onPreferenceChange(AppDrawsCloseButtonKey.self) { value in
                        appDrawsCloseButton = value
                    }
                    .onPreferenceChange(SwipeDismissIsPulledKey.self) { pulled in
                        isPulled = pulled
                        if hasAppBehind { onPull(pulled) }
                    }
            } else {
                MissingAppView(appID: appID)
            }
            if !appDrawsCloseButton, showsAppCloseButton {
                CloseButton { navigator.closeApp() }
                    .padding(Theme.Spacing.l)
            }
        }
        .persistentSystemOverlays(.hidden)
    }
}

extension AppContainerView {
    /// Closing goes Home. Going back returns to the app that opened this one, if any.
    private var closeAction: AppCloseAction {
        guard let id = navigator.returnAppID else { return AppCloseAction { navigator.closeApp() } }
        let title = registry.app(id)?.title ?? KnownAppID.displayName(for: id)
        return AppCloseAction(backTitle: title, back: { navigator.goBack() }) { navigator.closeApp() }
    }
}

/// Shown when something asks for an app no installed module provides.
struct MissingAppView: View {
    let appID: String
    @Environment(ShellNavigator.self) private var navigator

    var body: some View {
        EmptyStateView(
            "\(KnownAppID.displayName(for: appID)) Isn't Available",
            message: "This part of HomePad isn't installed in this version yet.",
            systemImage: "app.dashed",
            actionTitle: "Go Home",
            action: navigator.goHome
        )
    }
}

extension KnownAppID {
    /// A readable name for an app ID, even when its module is missing.
    static func displayName(for id: String) -> String {
        let names = [
            "home": "Home", "cameras": "Cameras", "nowplaying": "Now Playing", "music": "Music",
            "timers": "Timers", "recipes": "Recipes", "calendar": "Calendar", "reminders": "Reminders",
            "weather": "Weather", "worldclock": "World Clock", "photos": "Photos",
            "intercom": "Intercom", "mirror": "Mirror", "faces": "Faces", "assistant": "Assistant",
            "cameralab": "Camera Lab", "floorplan": "Floor Plan", "board": "Board", "settings": "Settings",
            "dashboards": "Dashboards",
        ]
        return names[id] ?? id.capitalized
    }
}
