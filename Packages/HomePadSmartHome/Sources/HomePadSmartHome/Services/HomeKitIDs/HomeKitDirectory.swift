import Foundation

/// What one HomePad calls each of its HomeKit objects: for each `hk:` ID, the
/// home, room, name and kind it has there. Every HomePad shares its own with
/// the household's other HomePads, which find their own object with the same
/// home, room, name and kind (`HomeKitIDMatcher`). HomeKit gives one accessory
/// a different identifier on every iPad, so this is how an ID saved on one
/// HomePad (a favorite, a widget's accessory, a face's camera) shows the same
/// thing on the others.
///
/// It covers every home, not only the one shown, so references made while
/// another home was picked still translate.
struct HomeKitDirectory: Codable, Equatable, Sendable {
    /// Sorted by ID, so the same objects always make the same document.
    var entries: [Entry]

    init(entries: [Entry]) {
        self.entries = entries.sorted { $0.id < $1.id }
    }

    /// One accessory service, group, camera or scene.
    struct Entry: Codable, Hashable, Sendable {
        /// The unified ID, `hk:<uuid>`.
        var id: String
        /// The HomeKit service type for a service, else `group`, `camera` or `scene`.
        var kind: String
        var home: String
        var room: String?
        var name: String
        /// The accessory a service or camera belongs to, which tells apart two
        /// services with one name in one room. Nil for groups and scenes.
        var accessory: String?

        init(id: String, kind: String, home: String, room: String? = nil, name: String, accessory: String? = nil) {
            self.id = id
            self.kind = kind
            self.home = home
            self.room = room
            self.name = name
            self.accessory = accessory
        }

        /// What two HomePads compare: the kind, home, room and name, each as
        /// people would read it.
        var key: Key {
            Key(kind: kind, home: Self.normalized(home), room: Self.normalized(room ?? ""), name: Self.normalized(name))
        }

        /// The accessory's name as it is compared.
        var accessoryKey: String {
            Self.normalized(accessory ?? "")
        }

        /// Trimmed, single spaces, no case, accents or width, so "Living  Room"
        /// and "living room" are one room.
        static func normalized(_ text: String) -> String {
            text.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
                .split(whereSeparator: \.isWhitespace)
                .joined(separator: " ")
        }
    }

    /// An entry's kind, home, room and name as they are compared.
    struct Key: Hashable, Sendable {
        var kind: String
        var home: String
        var room: String
        var name: String
    }

    /// The kinds that are not a HomeKit service type.
    enum Kind {
        static let group = "group"
        static let camera = "camera"
        static let scene = "scene"
    }
}
