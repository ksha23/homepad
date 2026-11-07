import HomePadCore

/// What is on screen when someone asks, as plain sentences for the system
/// prompt, so "unlock this door" or "add these ingredients" reaches the right
/// thing. The shell says which app is open (`AppServices.visibleAppID`), and
/// the module that owns it describes it (`ScreenContextProvider`).
@MainActor
enum ScreenContextReader {
    /// For example "The Recipes app. The recipe card for Shakshuka…". Nil on a
    /// face, on the Home Screen and in the Assistant app, unless something such
    /// as the doorbell shows over every screen.
    ///
    /// Personal summaries, and every app that needs recognition, stay out until
    /// someone is recognized, the same rule personal tools follow.
    static func describe(visibleAppID: String?, registry: ModuleRegistry, isPersonalUnlocked: Bool) -> String? {
        var sentences: [String] = []
        if let id = visibleAppID, id != AssistantModule.appID, let app = registry.app(id),
           isPersonalUnlocked || !app.requiresRecognizedMember {
            sentences.append("The \(app.title) app.")
            sentences += summaries(registry.screenContexts.filter { $0.appID == id }, isPersonalUnlocked: isPersonalUnlocked)
        }
        sentences += summaries(registry.screenContexts.filter { $0.appID == nil }, isPersonalUnlocked: isPersonalUnlocked)
        return sentences.isEmpty ? nil : sentences.joined(separator: " ")
    }

    private static func summaries(_ providers: [ScreenContextProvider], isPersonalUnlocked: Bool) -> [String] {
        providers
            .filter { isPersonalUnlocked || !$0.isPersonal }
            .compactMap { $0.summary()?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }
}
