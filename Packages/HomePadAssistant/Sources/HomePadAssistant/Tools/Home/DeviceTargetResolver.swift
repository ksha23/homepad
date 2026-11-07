import Foundation
import HomePadCore

/// Finds the accessories a spoken phrase refers to, by name, room and kind.
/// "kitchen lights", "the fan", "everything in the office" and "living room
/// lights" (a lamp in the living room) all resolve without exact names.
enum DeviceTargetResolver {
    private static let everything: Set<String> = ["all", "everything", "every device", "all devices", "devices", "anything"]
    private static let stopWords: Set<String> = ["the", "all", "in", "on", "of", "my", "please", "and", "a", "every", "both"]
    /// Kinds people rarely mean when they say "everything".
    private static let passiveKinds: Set<AccessoryKind> = [.sensor, .camera, .doorbell]

    /// Words people use for each kind. Used for matching and for kind-only phrases.
    static let kindWords: [AccessoryKind: [String]] = [
        .light: ["light", "lamp", "bulb", "lighting", "chandelier"],
        .fan: ["fan"],
        .thermostat: ["thermostat", "heat", "heating", "ac", "air", "temperature", "climate", "hvac"],
        .lock: ["lock", "door", "deadbolt"],
        .garageDoor: ["garage", "door"],
        .cover: ["blind", "shade", "curtain", "cover", "shutter", "window"],
        .mediaPlayer: ["speaker", "tv", "television", "music", "media", "player", "homepod", "sonos"],
        .switchOutlet: ["plug", "outlet", "switch"],
        .airPurifier: ["purifier", "air"],
        .vacuum: ["vacuum", "robot"],
        .securitySystem: ["alarm", "security"],
        .sensor: ["sensor"],
        .camera: ["camera"],
        .doorbell: ["doorbell"],
    ]

    static func resolve(device: String?, room: String?, in accessories: [HomeAccessory]) -> [HomeAccessory] {
        collapsingGroups(matches(device: device, room: room, in: accessories))
    }

    /// A group and its members can both match ("the living room lights"). The
    /// group already controls its members, so they are dropped.
    static func collapsingGroups(_ matches: [HomeAccessory]) -> [HomeAccessory] {
        let groupIDs = Set(matches.filter(\.isGroup).map(\.id))
        return matches.filter { accessory in accessory.groupID.map { !groupIDs.contains($0) } ?? true }
    }

    private static func matches(device: String?, room: String?, in accessories: [HomeAccessory]) -> [HomeAccessory] {
        let inRoom = room.map { room in accessories.filter { matchesRoom($0, room) } } ?? accessories
        let phrase = normalize(device ?? "")
        if phrase.isEmpty || everything.contains(phrase) {
            return inRoom.filter { !passiveKinds.contains($0.kind) }
        }
        let exact = inRoom.filter { normalize($0.name) == phrase || normalize("\($0.room ?? "") \($0.name)") == phrase }
        if !exact.isEmpty { return exact }

        let words = tokens(phrase).filter { !stopWords.contains($0) && !everything.contains($0) }
        guard !words.isEmpty else { return inRoom.filter { !passiveKinds.contains($0.kind) } }
        return inRoom.filter { accessory in
            let haystack = Set(tokens(accessory.name) + tokens(accessory.room ?? "") + (kindWords[accessory.kind] ?? []))
            return words.allSatisfy(haystack.contains)
        }
    }

    static func matchesRoom(_ accessory: HomeAccessory, _ room: String) -> Bool {
        guard let accessoryRoom = accessory.room else { return false }
        let wanted = normalize(room)
        let actual = normalize(accessoryRoom)
        return !wanted.isEmpty && (actual.contains(wanted) || wanted.contains(actual))
    }

    /// Lowercased, punctuation removed, single spaces.
    static func normalize(_ text: String) -> String {
        text.lowercased()
            .replacingOccurrences(of: "’", with: "'")
            .components(separatedBy: CharacterSet.alphanumerics.union(.whitespaces).inverted)
            .joined()
            .split(separator: " ")
            .filter { $0 != "the" }
            .joined(separator: " ")
    }

    /// Words with a plural "s" removed, so "lights" matches "Light".
    static func tokens(_ text: String) -> [String] {
        normalize(text).split(separator: " ").map { word in
            word.count > 3 && word.hasSuffix("s") && !word.hasSuffix("ss") ? String(word.dropLast()) : String(word)
        }
    }
}
