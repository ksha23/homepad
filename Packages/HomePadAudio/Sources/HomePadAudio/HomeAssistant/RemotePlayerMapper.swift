import Foundation
import HomePadCore

/// Maps smart home media players (HomePods through Home Assistant's Apple TV or
/// AirPlay integrations, Sonos, Music Assistant players) to `AudioOutput`s.
enum RemotePlayerMapper {
    /// Every accessory of kind `.mediaPlayer`, sorted by room then name.
    /// Music Assistant's dashboard displays (device class `tv`) are left out, because they cannot play music.
    static func outputs(from accessories: [HomeAccessory]) -> [AudioOutput] {
        accessories
            .filter { $0.kind == .mediaPlayer }
            .filter { !($0.integration == MusicAssistantPlayer.integration && $0.deviceClass == "tv") }
            .sorted { ($0.room ?? "", $0.name) < ($1.room ?? "", $1.name) }
            .map { accessory in
                AudioOutput(
                    id: accessory.id,
                    name: displayName(for: accessory),
                    kind: .homeAssistantPlayer,
                    isActive: isPlaying(accessory),
                    volume: accessory.state.volume
                )
            }
    }

    /// "Kitchen HomePod" stays as is, "HomePod" in the Kitchen becomes "Kitchen HomePod".
    static func displayName(for accessory: HomeAccessory) -> String {
        guard let room = accessory.room, !room.isEmpty,
              !accessory.name.localizedCaseInsensitiveContains(room) else { return accessory.name }
        return "\(room) \(accessory.name)"
    }

    /// A player counts as active when it is on and has something loaded.
    static func isPlaying(_ accessory: HomeAccessory) -> Bool {
        accessory.state.isReachable && accessory.state.isOn != false && accessory.state.mediaTitle != nil
    }

    /// The Home Assistant entity ID for an accessory ID such as `ha:media_player.kitchen`.
    /// Nil for accessories that are not Home Assistant media players.
    static func entityID(for accessoryID: String) -> String? {
        let raw = accessoryID.hasPrefix("ha:") ? String(accessoryID.dropFirst(3)) : accessoryID
        return raw.hasPrefix("media_player.") ? raw : nil
    }

    /// Finds the speaker someone named ("kitchen homepod", "the kitchen", "Sonos").
    /// Exact names win, then names that contain every word, then any word match
    /// unless `strict` is set.
    static func find(_ spoken: String, in outputs: [AudioOutput], strict: Bool = false) -> AudioOutput? {
        let needle = normalize(spoken)
        guard !needle.isEmpty else { return nil }
        if let exact = outputs.first(where: { normalize($0.name) == needle }) { return exact }
        let words = needle.split(separator: " ").map(String.init)
        if let all = outputs.first(where: { output in words.allSatisfy(normalize(output.name).contains) }) { return all }
        guard !strict else { return nil }
        return outputs.first { output in
            let name = normalize(output.name)
            return words.contains { $0.count > 2 && name.contains($0) }
        }
    }

    private static let fillerWords: Set<String> = ["the", "on", "in", "speaker", "speakers", "please", "my"]

    private static func normalize(_ text: String) -> String {
        let cleaned = String(text.lowercased().map { (character: Character) -> Character in
            character.isLetter || character.isNumber ? character : " "
        })
        let words = cleaned.split(separator: " ").map(String.init)
        return words.filter { !fillerWords.contains($0) }.joined(separator: " ")
    }
}
