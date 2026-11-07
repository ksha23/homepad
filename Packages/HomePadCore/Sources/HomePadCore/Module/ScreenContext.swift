import Foundation

/// Says in a sentence or two what an app shows right now, so the assistant can
/// act on "unlock this door" or "add these ingredients". The module that owns
/// the app registers one with `ModuleRegistry.register(screenContext:)`. The
/// assistant asks it only while that app is on screen (`AppServices.visibleAppID`),
/// at the moment someone asks something, so nothing runs in between.
///
///     registry.register(screenContext: ScreenContextProvider(appID: "recipes") {
///         context.session.map { "A recipe card for \($0.recipe.title)." }
///     })
public struct ScreenContextProvider: Identifiable {
    public let id: String
    /// The app it describes. Nil for something drawn over every screen, such as
    /// the doorbell, which is asked whatever is open.
    public let appID: String?
    /// The summary shows personal content, such as a calendar day. The assistant
    /// leaves it out unless someone is recognized.
    public let isPersonal: Bool
    /// Plain sentences about what is on screen, or nil when there is nothing worth saying.
    public let summary: @MainActor () -> String?

    /// Describes an app while it is on screen.
    public init(appID: String, isPersonal: Bool = false, summary: @escaping @MainActor () -> String?) {
        self.init(id: appID, appID: appID, isPersonal: isPersonal, summary: summary)
    }

    /// Describes something with its own ID, over one app or (with a nil `appID`) over every screen.
    public init(id: String, appID: String?, isPersonal: Bool = false, summary: @escaping @MainActor () -> String?) {
        self.id = id
        self.appID = appID
        self.isPersonal = isPersonal
        self.summary = summary
    }
}
