import Foundation

/// Where new Spotify music goes for the account in use.
///
/// Spotify's Web API controls only the devices signed in to the same Spotify
/// account. So a member's music plays on this iPad only while the Spotify app
/// here is signed in as them. Otherwise it plays on their own phone, computer
/// or Connect speakers, and HomePad says whose Spotify this iPad has.
enum SpotifyTarget: Equatable {
    /// The Spotify app on this iPad, signed in to this account, open or not.
    case thisIPad
    /// One of this account's Connect devices.
    case device(SpotifyDevice)
    /// The Spotify app on this iPad is signed in to someone else, named here,
    /// and none of this account's devices is on.
    case thisIPadIsOthers(String)
    /// A device was picked, and none of this account's devices is on now.
    case noDevice

    /// - Parameters:
    ///   - chosen: The device picked in Play On, empty for this iPad.
    ///   - devices: This account's devices that are on.
    ///   - playing: The device this account plays on now, if any.
    ///   - thisIPadIsOthers: Whose Spotify the app on this iPad has, when it is not this account's.
    static func choose(chosen: String, devices: [SpotifyDevice], playing: SpotifyDevice?,
                       thisIPadIsOthers: String?) -> SpotifyTarget {
        if !chosen.isEmpty, let device = devices.first(where: { $0.id == chosen }) { return .device(device) }
        if chosen.isEmpty, thisIPadIsOthers == nil { return .thisIPad }
        if let active = devices.first(where: \.isActive) ?? playing { return .device(active) }
        if let other = thisIPadIsOthers { return .thisIPadIsOthers(other) }
        return .noDevice
    }
}
