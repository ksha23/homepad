import Foundation

/// The last volume the person chose for each set of speakers Apple's player
/// plays to, kept on this iPad (`AudioSettings.musicVolumes`), so a restart or
/// a reconnect to the same speakers picks up where they were left.
///
/// Speakers are known by the names AirPlay gives them ("Back Stereo Pair"),
/// sorted, so a group is the same speakers in whatever order AirPlay lists
/// them. A renamed speaker starts without a level. Only the newest `capacity`
/// sets are kept.
struct MusicVolumeMemory: Codable, Equatable, Sendable {
    struct Entry: Codable, Equatable, Sendable {
        var speakers: String
        var level: Double
    }

    static let capacity = 12

    /// Newest first.
    private(set) var entries: [Entry] = []

    /// The speakers a level was remembered for last.
    var lastSpeakers: String? { entries.first?.speakers }

    /// The level remembered last, for any speakers.
    var lastLevel: Double? { entries.first?.level }

    /// The level the person left these speakers at, nil for speakers never set.
    func level(for speakers: String) -> Double? {
        entries.first { $0.speakers == speakers }?.level
    }

    mutating func remember(_ level: Double, for speakers: String) {
        entries.removeAll { $0.speakers == speakers }
        entries.insert(Entry(speakers: speakers, level: min(max(level, 0), 1)), at: 0)
        if entries.count > Self.capacity {
            entries.removeLast(entries.count - Self.capacity)
        }
    }

    /// One key for the names AirPlay gives the speakers, nil without names.
    /// The iPad's own speaker reads "Speaker" and is kept as "iPad".
    static func speakers(names: [String]) -> String? {
        let named = names.map { $0 == "Speaker" ? RouteNaming.builtInName : $0 }
        let unique = Set(named).sorted()
        guard !unique.isEmpty else { return nil }
        return unique.joined(separator: " + ")
    }
}
