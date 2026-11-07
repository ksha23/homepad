import Foundation
import HomePadCore
import Observation

/// Find My's state: the devices Home Assistant tracks (or demo devices), whose
/// each one is, which the recognized person may see, their addresses, and
/// Play Sound.
///
/// Devices come from `services.smartHome.trackedDevices`, which the Smart Home
/// module keeps current from Home Assistant's own state changes over the one
/// connection it already has. Nothing here polls: views that read
/// `visibleDevices` redraw when a tracker changes.
@MainActor
@Observable
final class FindMyService {
    /// What the app shows instead of a map when there is nothing to show.
    enum Setup: Equatable {
        case ready
        /// Home Assistant is not connected, so there are no trackers.
        case noHomeAssistant
        /// Home Assistant is connected but tracks no device with GPS.
        case noTrackers
        /// Devices exist, but none is the recognized person's to see.
        case nothingForViewer
    }

    private(set) var soundStates: [TrackedDevice.ID: FindMySoundState] = [:]
    let addresses: FindMyAddressBook
    @ObservationIgnored private let services: AppServices
    /// Demo "last seen" times count from here, so they do not reset on every redraw.
    @ObservationIgnored private let demoStart: Date

    init(services: AppServices, addresses: FindMyAddressBook? = nil, demoStart: Date = Date()) {
        self.services = services
        self.addresses = addresses ?? FindMyAddressBook()
        self.demoStart = demoStart
    }

    var isDemo: Bool { services.settings[PersonalSettings.demoData] }

    // MARK: Devices

    /// Every device with its owner, hidden ones included, for Settings.
    var allDevices: [FindMyDevice] {
        let members = services.household.members
        let choices = services.settings[PersonalSettings.findMyOwners]
        return trackedDevices.map { tracked in
            let ownership = FindMyOwnerMatcher.ownership(of: tracked, choice: choices[tracked.id], members: members)
            let owner = ownership.memberID.flatMap { id in members.first { $0.id == id } }
            return FindMyDevice(tracked: tracked, ownership: ownership, owner: owner)
        }
    }

    /// What the recognized person may see (see `FindMyVisibilityPolicy`): their
    /// own devices first, then everyone else's by owner, then devices nobody owns.
    var visibleDevices: [FindMyDevice] {
        let viewer = viewer
        let policy = policy
        let me = viewer.unlockedMemberID
        return allDevices
            .filter { policy.isVisible($0.ownership, to: viewer) }
            .sorted { lhs, rhs in
                let left = (lhs.owner?.id == me ? 0 : lhs.owner == nil ? 2 : 1, lhs.owner?.name ?? "", lhs.title)
                let right = (rhs.owner?.id == me ? 0 : rhs.owner == nil ? 2 : 1, rhs.owner?.name ?? "", rhs.title)
                if left.0 != right.0 { return left.0 < right.0 }
                if left.1 != right.1 { return left.1.localizedStandardCompare(right.1) == .orderedAscending }
                return left.2.localizedStandardCompare(right.2) == .orderedAscending
            }
    }

    func device(_ id: TrackedDevice.ID?) -> FindMyDevice? {
        visibleDevices.first { $0.id == id }
    }

    var zones: [HomeZone] {
        isDemo ? FindMyDemoData.zones : services.smartHome.zones
    }

    var setup: Setup {
        if !visibleDevices.isEmpty { return .ready }
        if !trackedDevices.isEmpty { return .nothingForViewer }
        return services.smartHome.connectedBackends.contains(.homeAssistant) ? .noTrackers : .noHomeAssistant
    }

    /// The person in front of the screen, with the same rules the calendars use.
    var viewer: CalendarViewer {
        let household = services.household
        return CalendarViewer(
            memberID: household.activeMemberID,
            isUnlocked: household.isPersonalContentUnlocked,
            adminIDs: Set(household.members.filter(\.isAdmin).map(\.id))
        )
    }

    /// The member recognized right now, for "my iPad".
    var recognizedMember: HouseholdMember? {
        services.household.isPersonalContentUnlocked ? services.household.activeMember : nil
    }

    var policy: FindMyVisibilityPolicy {
        FindMyVisibilityPolicy(shareWithEveryone: services.settings[PersonalSettings.findMyShareWithEveryone])
    }

    private var trackedDevices: [TrackedDevice] {
        isDemo ? FindMyDemoData.devices(members: services.household.members, now: demoStart) : services.smartHome.trackedDevices
    }

    // MARK: Owners

    /// The choice an admin made for a device, nil while it is automatic.
    func ownerChoice(for id: TrackedDevice.ID) -> FindMyOwnerChoice? {
        services.settings[PersonalSettings.findMyOwners][id]
    }

    func setOwnerChoice(_ choice: FindMyOwnerChoice?, for id: TrackedDevice.ID) {
        var choices = services.settings[PersonalSettings.findMyOwners]
        choices[id] = choice
        services.settings[PersonalSettings.findMyOwners] = choices
    }

    /// The member automatic matching picks for a device, for Settings.
    func suggestedOwner(of device: FindMyDevice) -> HouseholdMember? {
        FindMyOwnerMatcher.suggestedOwner(of: device.tracked, members: services.household.members)
    }

    var members: [HouseholdMember] { services.household.members }

    // MARK: Addresses

    /// The address already known for where a device is, without looking it up.
    func cachedAddress(for device: TrackedDevice) -> String? {
        guard let latitude = device.latitude, let longitude = device.longitude else { return nil }
        if isDemo { return FindMyDemoData.address(latitude: latitude, longitude: longitude) }
        return addresses.cached(latitude: latitude, longitude: longitude)
    }

    /// The street address where a device is, looked up once per spot.
    func address(for device: TrackedDevice) async -> String? {
        guard let latitude = device.latitude, let longitude = device.longitude else { return nil }
        if isDemo { return FindMyDemoData.address(latitude: latitude, longitude: longitude) }
        return await addresses.address(latitude: latitude, longitude: longitude)
    }

    // MARK: Play Sound

    /// Rings a device the recognized person may see, and records what happened
    /// for its card. Throws with the reason when it could not be sent.
    func playSound(_ device: FindMyDevice) async throws {
        guard visibleDevices.contains(where: { $0.id == device.id }) else {
            throw SmartHomeError.requiresRecognizedMember
        }
        soundStates[device.id] = .sending
        do {
            if isDemo {
                try await Task.sleep(for: .milliseconds(600))
                guard device.tracked.canPlaySound else { throw Self.cannotRing(device) }
            } else {
                try await services.smartHome.playSound(onTrackedDevice: device.id)
            }
            soundStates[device.id] = .sent(Date(), device.tracked.source)
        } catch {
            soundStates[device.id] = .failed(FindMySoundState.reason(for: error))
            throw error
        }
    }

    /// Why a device from another integration, such as Life360, cannot ring.
    static func cannotRing(_ device: FindMyDevice) -> SmartHomeError {
        .backend("\(device.title) cannot play a sound. Only devices from the iCloud integration or the Home Assistant app can.")
    }
}
