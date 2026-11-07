import Foundation
import HomePadCore

/// What a HomePad reports about itself, so companions can show its faces,
/// apps and timers and offer remote control. Body of a `.status` message.
public struct HomePadStatus: Codable, Equatable, Sendable {
    /// A face or app the companion can switch to.
    public struct Choice: Codable, Equatable, Hashable, Sendable, Identifiable {
        public var id: String
        public var title: String
        public var systemImage: String

        public init(id: String, title: String, systemImage: String) {
            self.id = id
            self.title = title
            self.systemImage = systemImage
        }
    }

    public var deviceID: String
    public var name: String
    public var faces: [Choice]
    public var apps: [Choice]
    public var timers: [HomeTimer]
    public var scenes: [HomeScene]
    /// "Title, Artist" for lists. The full picture comes in `media.status`.
    public var nowPlaying: String?
    /// The `RemoteProtocol` version this HomePad speaks. Nil from HomePads made
    /// before music control, which speak `RemoteProtocol.base`.
    public var remoteVersion: Int?
    public var updatedAt: Date

    public init(deviceID: String, name: String, faces: [Choice] = [], apps: [Choice] = [], timers: [HomeTimer] = [],
                scenes: [HomeScene] = [], nowPlaying: String? = nil, remoteVersion: Int? = nil, updatedAt: Date = Date()) {
        self.deviceID = deviceID
        self.name = name
        self.faces = faces
        self.apps = apps
        self.timers = timers
        self.scenes = scenes
        self.nowPlaying = nowPlaying
        self.remoteVersion = remoteVersion
        self.updatedAt = updatedAt
    }

    /// The protocol version this HomePad speaks.
    public var speaksVersion: Int { remoteVersion ?? RemoteProtocol.base }

    /// True when this HomePad understands `command`.
    public func understands(_ command: RemoteCommand) -> Bool {
        speaksVersion >= command.minimumRemoteVersion
    }

    /// True when this HomePad takes music commands and pushes `media.status`.
    public var supportsMusic: Bool { speaksVersion >= RemoteProtocol.music }

    /// True when a phone or Mac can approve unlocks on this HomePad.
    public var supportsPersonalDevices: Bool { speaksVersion >= RemoteProtocol.personalDevices }
    /// True when the HomePad can show this phone's photos to its owner.
    public var supportsPhonePhotos: Bool { speaksVersion >= RemoteProtocol.phonePhotos }
    /// True when the HomePad can show this phone owner's own Apple Music.
    public var supportsMemberAppleMusic: Bool { speaksVersion >= RemoteProtocol.memberAppleMusic }
    /// True when the HomePad can show this phone's calendars and lists to its owner.
    public var supportsPhoneCalendars: Bool { speaksVersion >= RemoteProtocol.phoneCalendars }
}
