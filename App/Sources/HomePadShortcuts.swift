import AppIntents
import HomePadConnect

/// Siri phrases that work with no setup. Every phrase names the app, as Siri requires.
/// The intents live in HomePadConnect. App Shortcuts must be declared in the app
/// target because the build does not merge them from packages.
struct HomePadShortcuts: AppShortcutsProvider {
    static let shortcutTileColor: ShortcutTileColor = .teal

    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: AskHomePadIntent(),
            phrases: ["Ask \(.applicationName)", "Ask \(.applicationName) a question"],
            shortTitle: "Ask HomePad", systemImageName: "sparkles"
        )
        AppShortcut(
            intent: AnnounceIntent(),
            phrases: ["Announce with \(.applicationName)", "Make an announcement on \(.applicationName)", "Intercom with \(.applicationName)"],
            shortTitle: "Announce", systemImageName: "waveform"
        )
        AppShortcut(
            intent: StartTimerIntent(),
            phrases: ["Start a \(.applicationName) timer", "Set a timer on \(.applicationName)"],
            shortTitle: "Start Timer", systemImageName: "timer"
        )
        AppShortcut(
            intent: RunSceneIntent(),
            phrases: ["Run \(\.$scene) with \(.applicationName)", "Set \(\.$scene) on \(.applicationName)", "Run a scene with \(.applicationName)"],
            shortTitle: "Run Scene", systemImageName: "sparkles.rectangle.stack"
        )
        AppShortcut(
            intent: ControlAccessoryIntent(),
            phrases: ["Control \(\.$accessory) with \(.applicationName)", "Control an accessory with \(.applicationName)"],
            shortTitle: "Control Accessory", systemImageName: "lightbulb"
        )
        AppShortcut(
            intent: ShowCamerasIntent(),
            phrases: ["Show cameras on \(.applicationName)", "Show my cameras with \(.applicationName)"],
            shortTitle: "Show Cameras", systemImageName: "video"
        )
        AppShortcut(
            intent: SetFaceIntent(),
            phrases: ["Show the \(\.$face) face on \(.applicationName)", "Change the \(.applicationName) face"],
            shortTitle: "Set Face", systemImageName: "clock"
        )
    }
}
