import HomePadCore

/// What the shell's own app keeps between openings (see `@AppState`).
enum ShellAppState {
    /// The Settings pane on screen when Settings closed. Shared by the
    /// household, like the panes themselves.
    static let settingsPane = AppStateKey<String?>("settings.pane", default: nil)
}
