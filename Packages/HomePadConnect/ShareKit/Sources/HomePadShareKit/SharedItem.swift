import Foundation

/// Something sent to a HomePad: a link, a recipe, some text or a photo.
/// Photos travel as the message attachment (JPEG), not inside this body.
public struct SharedItem: Codable, Equatable, Identifiable, Sendable {
    public enum Kind: String, Codable, CaseIterable, Sendable {
        case link, recipe, text, photo

        public var title: String {
            switch self {
            case .link: "Link"
            case .recipe: "Recipe"
            case .text: "Note"
            case .photo: "Photo"
            }
        }

        public var systemImage: String {
            switch self {
            case .link: "link"
            case .recipe: "fork.knife"
            case .text: "text.quote"
            case .photo: "photo"
            }
        }
    }

    public var id: UUID
    public var kind: Kind
    /// For links and recipe links.
    public var url: URL?
    /// For notes and pasted recipes.
    public var text: String?
    public var title: String?
    /// Who sent it, for example "Kyle's iPhone".
    public var senderName: String
    /// One HomePad, or nil for every HomePad in the household.
    public var targetID: String?
    public var sentAt: Date

    public init(id: UUID = UUID(), kind: Kind, url: URL? = nil, text: String? = nil, title: String? = nil,
                senderName: String, targetID: String? = nil, sentAt: Date = Date()) {
        self.id = id
        self.kind = kind
        self.url = url
        self.text = text
        self.title = title
        self.senderName = senderName
        self.targetID = targetID
        self.sentAt = sentAt
    }

    /// Guesses recipe vs plain link from the URL, for the Share extension.
    public static func classify(_ url: URL) -> Kind {
        let text = url.absoluteString.lowercased()
        let hints = ["recipe", "cooking", "allrecipes", "seriouseats", "bonappetit", "epicurious", "food52", "smittenkitchen", "budgetbytes"]
        return hints.contains(where: text.contains) ? .recipe : .link
    }
}
