import Foundation

/// Which smart home system an accessory, scene or camera comes from.
public enum SmartHomeBackend: String, Codable, Hashable, Sendable, CaseIterable {
    case homeKit
    case homeAssistant
    case demo

    public var displayName: String {
        switch self {
        case .homeKit: "Apple Home"
        case .homeAssistant: "Home Assistant"
        case .demo: "Demo"
        }
    }
}

public enum AccessoryKind: String, Codable, Hashable, Sendable, CaseIterable {
    case light
    case switchOutlet
    case fan
    case thermostat
    case lock
    case garageDoor
    case cover          // blinds, shades, curtains
    case camera
    case doorbell
    case sensor
    case mediaPlayer
    case securitySystem
    case airPurifier
    case vacuum
    case other

    /// SF Symbol used by default when a module has nothing better.
    public var systemImage: String {
        switch self {
        case .light: "lightbulb.fill"
        case .switchOutlet: "poweroutlet.type.b.fill"
        case .fan: "fan.fill"
        case .thermostat: "thermometer.medium"
        case .lock: "lock.fill"
        case .garageDoor: "door.garage.closed"
        case .cover: "blinds.horizontal.closed"
        case .camera: "video.fill"
        case .doorbell: "bell.fill"
        case .sensor: "sensor.fill"
        case .mediaPlayer: "hifispeaker.fill"
        case .securitySystem: "shield.lefthalf.filled"
        case .airPurifier: "air.purifier.fill"
        case .vacuum: "fan.floor.fill"
        case .other: "square.grid.2x2.fill"
        }
    }
}

public enum AccessoryCapability: String, Codable, Hashable, Sendable {
    case power, brightness, colorTemperature, color
    case targetTemperature, hvacMode
    case lock, position, volume, playback
}

public enum HVACMode: String, Codable, Hashable, Sendable, CaseIterable {
    case off, heat, cool, auto, fanOnly, dry
}

public enum LockState: String, Codable, Hashable, Sendable {
    case locked, unlocked, jammed, locking, unlocking, unknown
}

public enum DoorState: String, Codable, Hashable, Sendable {
    case open, closed, opening, closing, stopped, unknown
}

public enum TemperatureUnit: String, Codable, Hashable, Sendable {
    case celsius, fahrenheit
}

/// A backend-neutral snapshot of an accessory's state. Every field is optional,
/// so a backend only fills in what the device actually reports.
public struct AccessoryState: Codable, Hashable, Sendable {
    public var isOn: Bool?
    /// 0...1. Also the speed level for fans and air purifiers.
    public var brightness: Double?
    public var colorTemperatureKelvin: Int?
    public var hue: Double?                     // 0...360
    public var saturation: Double?              // 0...1
    public var currentTemperature: Double?
    public var targetTemperature: Double?
    public var temperatureUnit: TemperatureUnit?
    public var hvacMode: HVACMode?
    public var humidity: Double?                // 0...100
    public var lockState: LockState?
    public var position: Double?                // 0 closed ... 1 open
    public var doorState: DoorState?
    public var isActive: Bool?                  // motion, contact, occupancy
    public var sensorValue: Double?
    public var sensorUnit: String?
    public var batteryLevel: Double?            // 0...1
    public var mediaTitle: String?
    public var mediaArtist: String?
    public var mediaArtworkURL: URL?
    public var mediaPosition: TimeInterval?
    public var mediaDuration: TimeInterval?
    /// When `mediaPosition` was reported, so progress can be extrapolated while playing.
    public var mediaPositionUpdatedAt: Date?
    public var mediaAlbum: String?
    /// Accessory IDs of the players this one plays in sync with (multi-room), itself
    /// included when it leads the group. Nil when the backend does not group players.
    public var mediaGroupMemberIDs: [String]?
    public var isPlaying: Bool?
    public var volume: Double?                  // 0...1
    public var isReachable: Bool

    public init(
        isOn: Bool? = nil, brightness: Double? = nil, colorTemperatureKelvin: Int? = nil,
        hue: Double? = nil, saturation: Double? = nil, currentTemperature: Double? = nil,
        targetTemperature: Double? = nil, temperatureUnit: TemperatureUnit? = nil,
        hvacMode: HVACMode? = nil, humidity: Double? = nil, lockState: LockState? = nil,
        position: Double? = nil, doorState: DoorState? = nil, isActive: Bool? = nil,
        sensorValue: Double? = nil, sensorUnit: String? = nil, batteryLevel: Double? = nil,
        mediaTitle: String? = nil, mediaArtist: String? = nil, volume: Double? = nil,
        isReachable: Bool = true, mediaArtworkURL: URL? = nil, mediaPosition: TimeInterval? = nil,
        mediaDuration: TimeInterval? = nil, mediaPositionUpdatedAt: Date? = nil, isPlaying: Bool? = nil,
        mediaAlbum: String? = nil, mediaGroupMemberIDs: [String]? = nil
    ) {
        self.isOn = isOn
        self.brightness = brightness
        self.colorTemperatureKelvin = colorTemperatureKelvin
        self.hue = hue
        self.saturation = saturation
        self.currentTemperature = currentTemperature
        self.targetTemperature = targetTemperature
        self.temperatureUnit = temperatureUnit
        self.hvacMode = hvacMode
        self.humidity = humidity
        self.lockState = lockState
        self.position = position
        self.doorState = doorState
        self.isActive = isActive
        self.sensorValue = sensorValue
        self.sensorUnit = sensorUnit
        self.batteryLevel = batteryLevel
        self.mediaTitle = mediaTitle
        self.mediaArtist = mediaArtist
        self.volume = volume
        self.isReachable = isReachable
        self.mediaArtworkURL = mediaArtworkURL
        self.mediaPosition = mediaPosition
        self.mediaDuration = mediaDuration
        self.mediaPositionUpdatedAt = mediaPositionUpdatedAt
        self.isPlaying = isPlaying
        self.mediaAlbum = mediaAlbum
        self.mediaGroupMemberIDs = mediaGroupMemberIDs
    }
}

public struct HomeAccessory: Identifiable, Codable, Hashable, Sendable {
    /// Backend-prefixed and stable, for example `ha:light.kitchen` or `hk:<uuid>`.
    public var id: String
    public var name: String
    public var room: String?
    public var kind: AccessoryKind
    public var backend: SmartHomeBackend
    public var capabilities: Set<AccessoryCapability>
    public var state: AccessoryState
    /// The integration that provides the accessory inside its backend, for example
    /// `music_assistant`, `sonos` or `hue` for Home Assistant entities. Nil when unknown.
    public var integration: String?
    /// The backend's device class, for example `speaker` or `tv` for Home Assistant
    /// media players. Nil when the backend reports none.
    public var deviceClass: String?
    /// The device's model as its backend reports it, for example "HomePod mini" or "Sonos Era 100".
    public var deviceModel: String?
    /// For a group (an Apple Home group of several accessories): the accessories
    /// it controls together. Nil for a single accessory.
    public var memberIDs: [String]?
    /// For an accessory inside a group: the group's ID. Lists show the group in
    /// its place, and the group's detail shows its members.
    public var groupID: String?

    public init(
        id: String, name: String, room: String? = nil, kind: AccessoryKind,
        backend: SmartHomeBackend, capabilities: Set<AccessoryCapability> = [],
        state: AccessoryState = AccessoryState(), integration: String? = nil, deviceClass: String? = nil,
        deviceModel: String? = nil, memberIDs: [String]? = nil, groupID: String? = nil
    ) {
        self.id = id
        self.name = name
        self.room = room
        self.kind = kind
        self.backend = backend
        self.capabilities = capabilities
        self.state = state
        self.integration = integration
        self.deviceClass = deviceClass
        self.deviceModel = deviceModel
        self.memberIDs = memberIDs
        self.groupID = groupID
    }

    /// True for a group of accessories controlled together.
    public var isGroup: Bool { memberIDs != nil }

    /// One short line such as "On, 70%", "Locked" or "72°" for tiles.
    public var statusText: String {
        if !state.isReachable { return "No Response" }
        switch kind {
        case .lock:
            return (state.lockState ?? .unknown).rawValue.capitalized
        case .thermostat:
            if let target = state.targetTemperature { return "\(Int(target.rounded()))°" }
            if let current = state.currentTemperature { return "\(Int(current.rounded()))°" }
        case .cover, .garageDoor:
            if let position = state.position { return position <= 0.01 ? "Closed" : "\(Int(position * 100))% Open" }
            if let door = state.doorState { return door.rawValue.capitalized }
        case .sensor:
            if let value = state.sensorValue { return "\(value.formatted(.number.precision(.fractionLength(0...1))))\(state.sensorUnit ?? "")" }
            if let active = state.isActive { return active ? "Detected" : "Clear" }
        case .mediaPlayer:
            if let title = state.mediaTitle { return title }
        default:
            break
        }
        guard let isOn = state.isOn else { return "" }
        if isOn, let brightness = state.brightness { return "On, \(Int(brightness * 100))%" }
        return isOn ? "On" : "Off"
    }
}

public struct HomeScene: Identifiable, Codable, Hashable, Sendable {
    public var id: String
    public var name: String
    public var backend: SmartHomeBackend
    public var systemImage: String

    public init(id: String, name: String, backend: SmartHomeBackend, systemImage: String = "sparkles") {
        self.id = id
        self.name = name
        self.backend = backend
        self.systemImage = systemImage
    }
}

public struct HomeCamera: Identifiable, Codable, Hashable, Sendable {
    public var id: String
    public var name: String
    public var room: String?
    public var backend: SmartHomeBackend
    public var isDoorbell: Bool
    /// For backends that expose plain URLs (Home Assistant MJPEG or HLS).
    public var streamURL: URL?
    public var snapshotURL: URL?

    public init(
        id: String, name: String, room: String? = nil, backend: SmartHomeBackend,
        isDoorbell: Bool = false, streamURL: URL? = nil, snapshotURL: URL? = nil
    ) {
        self.id = id
        self.name = name
        self.room = room
        self.backend = backend
        self.isDoorbell = isDoorbell
        self.streamURL = streamURL
        self.snapshotURL = snapshotURL
    }
}

public enum AccessoryCommand: Hashable, Sendable {
    case setPower(Bool)
    case toggle
    case setBrightness(Double)              // 0...1
    case setColorTemperature(kelvin: Int)
    case setHueSaturation(hue: Double, saturation: Double)
    case setTargetTemperature(Double)
    case setHVACMode(HVACMode)
    case lock
    case unlock
    case setPosition(Double)                // 0...1
    case open
    case close
    case stop
    case setVolume(Double)                  // 0...1
    case play
    case pause
    case nextTrack
    case previousTrack
}

public enum SmartHomeError: LocalizedError, Sendable {
    case notConnected(SmartHomeBackend)
    case accessoryNotFound(String)
    case unsupported(String)
    case requiresRecognizedMember
    case backend(String)

    public var errorDescription: String? {
        switch self {
        case .notConnected(let backend): "\(backend.displayName) is not connected."
        case .accessoryNotFound(let id): "Could not find accessory \(id)."
        case .unsupported(let what): "\(what) is not supported by this accessory."
        case .requiresRecognizedMember: "This needs a recognized household member."
        case .backend(let message): message
        }
    }
}

public extension Array where Element == HomeAccessory {
    /// What a list of tiles shows: each group in place of its members, as Apple Home does.
    var hidingGroupMembers: [HomeAccessory] { filter { $0.groupID == nil } }

    /// Each device once, without the groups, for counts such as "3 lights on".
    var withoutGroups: [HomeAccessory] { filter { !$0.isGroup } }
}
