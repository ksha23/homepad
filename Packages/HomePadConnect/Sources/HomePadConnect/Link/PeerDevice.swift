import Foundation

/// Another HomePad, iPhone or Mac seen on the network or connected to us.
public struct PeerDevice: Identifiable, Hashable, Sendable {
    public var id: String
    public var name: String
    public var kind: DeviceKind
    public var householdID: String?
    /// The device shows a pairing code right now.
    public var isAcceptingPairing: Bool
    /// An authenticated session is open.
    public var isConnected: Bool
    public var lastSeen: Date
    /// The session a message arrived on. Set only on the device handed to
    /// message handlers, so a feature can answer on that same session and
    /// tell a new session with the same device ID from the one it trusted.
    public var sessionID: UUID?

    public init(id: String, name: String, kind: DeviceKind, householdID: String? = nil,
                isAcceptingPairing: Bool = false, isConnected: Bool = false, lastSeen: Date = Date()) {
        self.id = id
        self.name = name
        self.kind = kind
        self.householdID = householdID
        self.isAcceptingPairing = isAcceptingPairing
        self.isConnected = isConnected
        self.lastSeen = lastSeen
    }

    public func isMember(of household: HouseholdCredentials?) -> Bool {
        guard let household, let householdID else { return false }
        return householdID == household.id
    }
}

/// What a device publishes in its Bonjour TXT record. No secrets.
public struct PeerAdvert: Equatable, Sendable {
    public static let serviceType = "_homepad._tcp"

    public var deviceID: String
    public var name: String
    public var kind: DeviceKind
    public var householdID: String?
    public var acceptsPairing: Bool
    public var protocolVersion: Int

    public init(deviceID: String, name: String, kind: DeviceKind, householdID: String?, acceptsPairing: Bool,
                protocolVersion: Int = HandshakeEngine.protocolVersion) {
        self.deviceID = deviceID
        self.name = name
        self.kind = kind
        self.householdID = householdID
        self.acceptsPairing = acceptsPairing
        self.protocolVersion = protocolVersion
    }

    public init?(txt: [String: String]) {
        guard let id = txt["id"], !id.isEmpty, let kind = txt["kind"].flatMap(DeviceKind.init(rawValue:)) else { return nil }
        self.init(deviceID: id, name: txt["name"] ?? kind.displayName, kind: kind,
                  householdID: txt["hh"].flatMap { $0.isEmpty ? nil : $0 },
                  acceptsPairing: txt["pair"] == "1", protocolVersion: txt["v"].flatMap(Int.init) ?? 1)
    }

    public var txt: [String: String] {
        ["id": deviceID, "name": name, "kind": kind.rawValue, "hh": householdID ?? "",
         "pair": acceptsPairing ? "1" : "0", "v": String(protocolVersion)]
    }

    var device: PeerDevice {
        PeerDevice(id: deviceID, name: name, kind: kind, householdID: householdID, isAcceptingPairing: acceptsPairing)
    }
}
