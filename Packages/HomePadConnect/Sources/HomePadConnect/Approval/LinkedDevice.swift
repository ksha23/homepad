import CryptoKit
import Foundation
import HomePadCore
import Observation

/// On a HomePad: a phone or Mac allowed to approve unlocks for one member.
struct LinkedDevice: Codable, Equatable, Identifiable, Sendable {
    /// The device's peer link ID.
    var id: String
    var name: String
    var kind: DeviceKind
    var memberID: UUID
    /// The device's P256 signing key, raw representation.
    var publicKey: Data
    /// The `RemoteProtocol` version it spoke when it linked.
    var remoteVersion: Int
    var linkedAt: Date
    /// The IDs this HomePad knew the member by before it joined a household's
    /// setup, oldest first. The device carries over what it keeps for them.
    var formerMemberIDs: [UUID]? = nil

    /// True when `signature` is this device's signature over `data`.
    func signed(_ data: Data, with signature: Data) -> Bool {
        guard let key = try? P256.Signing.PublicKey(rawRepresentation: publicKey),
              let signature = try? P256.Signing.ECDSASignature(rawRepresentation: signature) else { return false }
        return key.isValidSignature(signature, for: data)
    }

    /// True when the device speaks a protocol with approval in it.
    var canApprove: Bool { remoteVersion >= RemoteProtocol.personalDevices }
}

/// On a HomePad: the linked devices, kept in this HomePad's settings. Public
/// keys only, no secrets. Each device approves for one member at most.
@MainActor
@Observable
final class LinkedDeviceStore {
    private(set) var devices: [LinkedDevice]
    @ObservationIgnored private let settings: SettingsStore

    static let key = SettingKey<[LinkedDevice]>("connect.approval.devices", default: [])

    init(settings: SettingsStore) {
        self.settings = settings
        self.devices = settings[Self.key]
    }

    func device(_ id: String) -> LinkedDevice? { devices.first { $0.id == id } }

    func devices(for member: UUID) -> [LinkedDevice] { devices.filter { $0.memberID == member } }

    /// Adds a link, replacing any other link of the same device.
    func save(_ device: LinkedDevice) {
        devices.removeAll { $0.id == device.id }
        devices.append(device)
        persist()
    }

    func remove(_ id: String) {
        guard devices.contains(where: { $0.id == id }) else { return }
        devices.removeAll { $0.id == id }
        persist()
    }

    /// Keeps a person's devices linked to them under the ID the household
    /// knows them by. Returns the devices that moved.
    @discardableResult
    func moveMember(from old: UUID, to new: UUID) -> [String] {
        let moved = devices.filter { $0.memberID == old }.map(\.id)
        guard !moved.isEmpty else { return [] }
        for index in devices.indices where devices[index].memberID == old {
            devices[index].memberID = new
            devices[index].formerMemberIDs = (devices[index].formerMemberIDs ?? []) + [old]
        }
        persist()
        return moved
    }

    /// Drops links to people no longer in the household.
    func prune(keeping members: Set<UUID>) {
        let kept = devices.filter { members.contains($0.memberID) }
        guard kept.count != devices.count else { return }
        devices = kept
        persist()
    }

    private func persist() {
        settings[Self.key] = devices
    }
}
