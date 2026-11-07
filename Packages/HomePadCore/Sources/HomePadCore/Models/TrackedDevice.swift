import Foundation

/// A phone, tablet, watch or computer whose location a smart home backend
/// reports. For Home Assistant that is a GPS device tracker from the iCloud
/// integration, the Companion app or another integration such as Life360.
///
/// Locations are personal. Show them only through the Personal module's Find
/// My rules, which decide who may see whose devices.
public struct TrackedDevice: Identifiable, Hashable, Sendable {
    /// Where the location comes from, which also decides how a sound is played.
    public enum Source: String, Codable, Hashable, Sendable {
        /// Home Assistant's iCloud integration, which reads Find My through an
        /// Apple Account. Plays a sound with `icloud.play_sound`.
        case iCloud
        /// The Home Assistant Companion app on the device itself. Rings with a
        /// critical notification.
        case companionApp
        /// Any other integration with GPS. It cannot play a sound.
        case other
    }

    /// Where the device is, in the backend's own zones.
    public enum Place: Hashable, Sendable {
        case home
        /// Inside another zone, by its name, for example "Work".
        case zone(String)
        /// Outside every zone.
        case away
        /// The backend has no location for it right now.
        case unknown
    }

    /// Backend-prefixed and stable, for example `ha:device_tracker.kyles_iphone`.
    public var id: String
    /// The name the backend shows, for example "Kyle's iPhone".
    public var name: String
    public var source: Source
    /// The integration that tracks it inside its backend, for example `icloud` or `mobile_app`.
    public var integration: String?
    /// The device's model, for example "iPhone 17 Pro", when the backend knows it.
    public var model: String?
    public var place: Place
    public var latitude: Double?
    public var longitude: Double?
    /// How far off the location may be, in meters.
    public var accuracy: Double?
    /// 0...1
    public var batteryLevel: Double?
    /// True while it charges or sits full on a charger.
    public var isCharging: Bool?
    /// When the backend last heard a new location or battery level.
    public var lastUpdated: Date
    /// Who the backend says owns it: a Home Assistant person that lists this
    /// tracker, or the owner's name from iCloud. Nil when it does not say.
    public var ownerName: String?

    public init(
        id: String, name: String, source: Source, integration: String? = nil, model: String? = nil,
        place: Place = .unknown, latitude: Double? = nil, longitude: Double? = nil, accuracy: Double? = nil,
        batteryLevel: Double? = nil, isCharging: Bool? = nil, lastUpdated: Date, ownerName: String? = nil
    ) {
        self.id = id
        self.name = name
        self.source = source
        self.integration = integration
        self.model = model
        self.place = place
        self.latitude = latitude
        self.longitude = longitude
        self.accuracy = accuracy
        self.batteryLevel = batteryLevel
        self.isCharging = isCharging
        self.lastUpdated = lastUpdated
        self.ownerName = ownerName
    }

    /// True when it has coordinates to put on a map.
    public var hasLocation: Bool { latitude != nil && longitude != nil }

    /// True when the backend can make it play a sound.
    public var canPlaySound: Bool { source != .other }
}

/// A named area devices can be in, such as Home or Work. Home Assistant calls
/// these zones and puts a device's zone in its tracker's state.
public struct HomeZone: Identifiable, Hashable, Sendable {
    /// Backend-prefixed, for example `ha:zone.home`.
    public var id: String
    public var name: String
    public var latitude: Double
    public var longitude: Double
    /// In meters.
    public var radius: Double
    /// The household's home zone.
    public var isHome: Bool

    public init(id: String, name: String, latitude: Double, longitude: Double, radius: Double, isHome: Bool = false) {
        self.id = id
        self.name = name
        self.latitude = latitude
        self.longitude = longitude
        self.radius = radius
        self.isHome = isHome
    }
}
