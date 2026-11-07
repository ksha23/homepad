import Foundation

/// A document each HomePad keeps about itself and shares with the household's
/// other HomePads, such as the names it knows its HomeKit accessories by.
///
/// It is the setup's third kind of owner, beside the household and each
/// person (`SharedDocumentDescriptor`): one per HomePad. Only the HomePad it
/// describes ever writes it, so two HomePads never overwrite each other's,
/// and every HomePad holds the latest one of every other. Connect carries
/// them with the shared setup, versions included, so a HomePad that was off
/// catches up, and passes on what it holds of a HomePad that is off now.
public struct HomePadDocumentDescriptor: Identifiable {
    /// The kind, named `<module>.<thing>`, for example `smarthome.homeKitDirectory`.
    public let id: String
    /// This HomePad's own document now. `.onlyThisHomePad` while it is not
    /// known yet (Apple Home still loading, say), which keeps the copy shared
    /// before. `.none` deletes it on the other HomePads.
    public let read: @MainActor () -> SharedDocumentValue
    /// Another HomePad's document arrived, with that HomePad's peer-link
    /// device ID. Nil content means it has none any more.
    public let apply: @MainActor (_ homePadID: String, _ content: JSONValue?) -> Void

    public init(id: String,
                read: @escaping @MainActor () -> SharedDocumentValue,
                apply: @escaping @MainActor (_ homePadID: String, _ content: JSONValue?) -> Void) {
        self.id = id
        self.read = read
        self.apply = apply
    }
}
