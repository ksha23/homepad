import Foundation

/// Whose a shared document is: the household's, or one person's.
public enum SharedDocumentOwner: Hashable, Sendable {
    /// The household's own, such as the guest Home Screen or the household's faces.
    case household
    /// One person's, by their member ID.
    case member(UUID)

    /// "household" or the member's UUID, the form a document travels under.
    public var key: String {
        switch self {
        case .household: "household"
        case .member(let id): id.uuidString
        }
    }

    /// Reads `key`. Nil for anything else.
    public init?(key: String) {
        if key == "household" {
            self = .household
        } else if let id = UUID(uuidString: key) {
            self = .member(id)
        } else {
            return nil
        }
    }

    /// The member's ID, nil for the household.
    public var memberID: UUID? {
        if case .member(let id) = self { return id }
        return nil
    }
}

/// What a module reads for one shared document on this iPad.
public enum SharedDocumentValue: Equatable, Sendable {
    /// Nothing saved, so the default shows. When the document was shared
    /// before, this spreads to the other HomePads as a deletion.
    case none
    /// What every HomePad in the household shows.
    case content(JSONValue)
    /// Saved, but it belongs to this iPad for now, such as a wallpaper photo
    /// from this iPad's library. Nothing is shared, and a change made on
    /// another HomePad still applies here.
    case onlyThisHomePad
}

/// A piece of the household's setup that a module shares with the other
/// HomePads in the household, such as each person's Home Screen or saved
/// faces. Connect carries the documents over the peer link, versions them and
/// resolves conflicts. The module only says how to read and apply one.
///
/// Rules a descriptor keeps:
/// - `read` returns only what every HomePad should show. What belongs to one
///   iPad (a photo from its library, its screen, its hardware) stays out.
/// - Reading right after applying returns what was applied, so a document
///   that arrives is never sent back as a change of this iPad's own.
/// - `apply` keeps whatever `read` leaves out, so this iPad's own parts survive.
public struct SharedDocumentDescriptor: Identifiable {
    /// Which owners have a document of this kind.
    public struct Owners: OptionSet, Sendable {
        public let rawValue: Int
        public init(rawValue: Int) { self.rawValue = rawValue }

        /// One for the household.
        public static let household = Owners(rawValue: 1)
        /// One for each person.
        public static let members = Owners(rawValue: 2)
    }

    /// The kind, named `<module>.<thing>`, for example `shell.homeScreen`.
    public let id: String
    public let owners: Owners
    /// The document as this iPad has it now.
    public let read: @MainActor (SharedDocumentOwner) -> SharedDocumentValue
    /// Shows a document from another HomePad. Nil content means it was
    /// deleted there, and this iPad goes back to the default.
    public let apply: @MainActor (SharedDocumentOwner, JSONValue?) -> Void

    public init(id: String, owners: Owners,
                read: @escaping @MainActor (SharedDocumentOwner) -> SharedDocumentValue,
                apply: @escaping @MainActor (SharedDocumentOwner, JSONValue?) -> Void) {
        self.id = id
        self.owners = owners
        self.read = read
        self.apply = apply
    }
}

public extension JSONValue {
    /// A Codable value as a JSON tree, for a shared document's content.
    init<Value: Encodable>(encoding value: Value) throws {
        self = try JSONDecoder().decode(JSONValue.self, from: JSONEncoder().encode(value))
    }

    /// The tree read back as a Codable value.
    func decoded<Value: Decodable>(as type: Value.Type) throws -> Value {
        try JSONDecoder().decode(type, from: JSONEncoder().encode(self))
    }
}
