import Foundation

/// Versions of the remote-control protocol between companions and HomePads.
///
/// A HomePad reports the version it speaks in `HomePadStatus.remoteVersion`.
/// A companion checks it before sending a command that needs a newer HomePad,
/// and says "Update HomePad" instead of sending something the HomePad would
/// drop. HomePads made before music control send no version and speak `base`.
///
/// Newer HomePads also answer every command with a `CommandReply`, and a
/// command they cannot read with `.unsupported`, so the next addition fails
/// politely even on a companion that skipped the version check.
public enum RemoteProtocol {
    /// Faces, apps, the face, timers, Ask and scenes.
    public static let base = 1
    /// Adds music: `.media` commands, `CommandReply`, `media.subscribe` and `media.status`.
    public static let music = 2
    /// Adds personal device approval: the `approval.*` messages, for the
    /// recognition gate's Use Personal Device.
    public static let personalDevices = 3
    /// Adds each person's own phone photos: the `photos.*` messages and the
    /// HomePad's key in `ApprovalLinkState`.
    public static let phonePhotos = 4
    /// Adds each person's own Apple Music: the `music.*` messages.
    public static let memberAppleMusic = 5
    /// Adds each person's own phone calendars and reminders lists: the
    /// `calendar.*` and `reminders.*` messages, and the kinds in a visit's hello.
    public static let phoneCalendars = 6
    /// What this build speaks.
    public static let current = phoneCalendars
}

/// Body of a `media.subscribe` message: a companion starts or stops watching a
/// HomePad's music. While it watches, the HomePad pushes `media.status` on every
/// change. Closing the session also stops it.
public struct MediaSubscription: Codable, Equatable, Sendable {
    public var isWatching: Bool

    public init(isWatching: Bool) {
        self.isWatching = isWatching
    }
}
