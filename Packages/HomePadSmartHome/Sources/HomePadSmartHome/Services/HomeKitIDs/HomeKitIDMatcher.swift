import Foundation

/// Pairs another HomePad's HomeKit objects with this HomePad's own, by home,
/// room, name and kind (`HomeKitDirectory.Entry.key`).
///
/// A pair is made only when it is certain. Where two objects share a key, the
/// name of the accessory they belong to decides, and if that leaves more than
/// one, the ID pairs with nothing, so a favorite never shows the wrong lamp.
/// The rule runs both ways: the object found here must lead back to the same
/// object there, so two of the other HomePad's objects never pair with one of
/// this HomePad's.
enum HomeKitIDMatcher {
    /// This HomePad's ID for each of `other`'s IDs it can pair, by the other HomePad's ID.
    static func translations(from other: HomeKitDirectory, to local: HomeKitDirectory) -> [String: String] {
        let localIndex = Index(local)
        let otherIndex = Index(other)
        var result: [String: String] = [:]
        for entry in other.entries {
            guard let match = localIndex.unique(for: entry),
                  otherIndex.unique(for: match)?.id == entry.id else { continue }
            result[entry.id] = match.id
        }
        return result
    }

    /// One directory's entries by key.
    private struct Index {
        let byKey: [HomeKitDirectory.Key: [HomeKitDirectory.Entry]]

        init(_ directory: HomeKitDirectory) {
            byKey = Dictionary(grouping: directory.entries, by: \.key)
        }

        /// The one entry here with the same key as `entry`, narrowed by the
        /// accessory's name when the key alone is not enough. Nil for none or several.
        func unique(for entry: HomeKitDirectory.Entry) -> HomeKitDirectory.Entry? {
            let sameKey = byKey[entry.key] ?? []
            if sameKey.count == 1 { return sameKey[0] }
            let sameAccessory = sameKey.filter { $0.accessoryKey == entry.accessoryKey }
            return sameAccessory.count == 1 ? sameAccessory[0] : nil
        }
    }
}
