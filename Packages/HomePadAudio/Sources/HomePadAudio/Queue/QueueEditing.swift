import Foundation

/// What a player's queue allows right now, for Up Next and the shuffle and repeat buttons.
struct QueueAbilities: OptionSet, Hashable, Sendable {
    let rawValue: Int
    /// Songs after the current one can be moved, removed and cleared.
    static let edit = QueueAbilities(rawValue: 1 << 0)
    /// Songs, albums and playlists can be added with Play Next and Play Later.
    static let add = QueueAbilities(rawValue: 1 << 1)
    static let shuffle = QueueAbilities(rawValue: 1 << 2)
    static let `repeat` = QueueAbilities(rawValue: 1 << 3)

    static let all: QueueAbilities = [.edit, .add, .shuffle, .repeat]
}

/// A local player whose queue HomePad can change: Apple Music and the simulator demo.
@MainActor
protocol QueueEditing: PlaybackSource {
    var queueAbilities: QueueAbilities { get }
    var shuffle: Bool { get }
    var repeatMode: MusicRepeatMode { get }
    /// A short line about where the queue came from, such as "Playing from Night Signals".
    var queueOrigin: String? { get }

    func moveUpNext(from offsets: IndexSet, to destination: Int) async
    func removeUpNext(at offsets: IndexSet) async
    func clearUpNext() async
    func setShuffle(_ isOn: Bool)
    func setRepeat(_ mode: MusicRepeatMode)
}
