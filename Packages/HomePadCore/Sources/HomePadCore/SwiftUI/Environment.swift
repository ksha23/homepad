import SwiftUI

public extension EnvironmentValues {
    /// Nearest person's distance bucket. Faces and widgets use it to show
    /// big glanceable info from across the room and more detail up close.
    @Entry var proximity: ProximityLevel = .far

    /// Set by the kiosk controller. `.night` means render in the red night palette.
    @Entry var displayCondition: DisplayCondition = .ambient

    /// True when the view is shown inside a face or widget preview thumbnail,
    /// where motion cannot be seen. Draw a still, cheap version.
    @Entry var isThumbnail: Bool = false

    /// True when a face draws blurred behind the Home Screen. Like HomeView's,
    /// it then draws only its picture or background: no time, date, text,
    /// tiles or widgets. Redraw rarely: motion barely shows through the blur,
    /// and every redraw blurs the screen again.
    @Entry var isFrosted: Bool = false

    /// True for a module overlay while the always-on face is the screen, not the
    /// Home Screen or an app. The face is read from across the room, so an overlay
    /// that shows personal text keeps it private there. Set by the shell.
    @Entry var isOnFace: Bool = false

    /// True when a face, or a widget on one, may run continuous motion:
    /// implicit `repeatForever` animations, slow drifts and particles. False in
    /// thumbnails, behind the Home Screen's frost (every frame there re-blurs
    /// the screen), and while the display is dimmed, red for the night or
    /// asleep. Draw the same picture then, only still.
    var allowsContinuousMotion: Bool {
        !isThumbnail && !isFrosted && displayCondition.allowsMotion
    }
}

public extension View {
    /// Injects the shared container and registry. The app root calls this once.
    func homePadEnvironment(services: AppServices, registry: ModuleRegistry) -> some View {
        modifier(HomePadEnvironment(services: services, registry: registry))
    }
}

/// Reads the display condition and presence in its own body, so a new presence
/// reading (several a second while someone moves) redraws this modifier rather
/// than re-running the app's scene body.
private struct HomePadEnvironment: ViewModifier {
    let services: AppServices
    let registry: ModuleRegistry

    func body(content: Content) -> some View {
        let snapshot = services.presence.snapshot
        content
            .environment(services)
            .environment(registry)
            .environment(services.household)
            .environment(services.settings)
            .environment(services.appState)
            .environment(\.displayCondition, services.displayCondition)
            .environment(\.proximity, snapshot.isSomeonePresent ? snapshot.proximity : .far)
    }
}

public extension Color {
    /// Parses "#RRGGBB" or "RRGGBB". Falls back to gray.
    init(hex: String) {
        let cleaned = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#")).uppercased()
        var value: UInt64 = 0
        guard cleaned.count == 6, Scanner(string: cleaned).scanHexInt64(&value) else {
            self = .gray
            return
        }
        self = Color(
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255
        )
    }
}
