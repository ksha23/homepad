import HomePadCore

/// What the Assistant app keeps between openings (see `@AppState`). The chat
/// itself is the person's history, kept by `ConversationStore`.
enum AssistantAppState {
    /// Chat or Settings, for each recognized person, and one shared while
    /// nobody is recognized.
    static let tab = AppStateKey("assistant.tab", default: AssistantAppTab.chat, scope: .member)

    /// The tab to reopen on: Settings only for someone who may change them,
    /// so nobody reopens on "Admins Only".
    static func restoredTab(_ saved: AssistantAppTab, canChangeSettings: Bool) -> AssistantAppTab {
        saved == .settings && !canChangeSettings ? .chat : saved
    }
}
