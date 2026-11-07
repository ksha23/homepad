import CryptoKit
import Foundation
import HomePadCore
import Observation

/// On a HomePad: Use Personal Device. Installed as `services.personalDevices`.
///
/// - Linking: a member's phone or Mac sends its public key (`approval.link`).
///   Someone at this HomePad allows it, and the member must be recognized
///   here or the iPad's owner must pass Face ID or the passcode.
/// - Approving: the gate asks, this HomePad sends an `approval.request` to
///   the member's linked devices and waits up to 30 seconds. `ApprovalLedger`
///   checks every answer.
@MainActor
@Observable
public final class PersonalDeviceApprover: PersonalDeviceService {
    /// A device waiting for someone at this HomePad to allow its link.
    public struct PendingLink: Identifiable, Equatable {
        let device: LinkedDevice
        let expiresAt: Date

        public var id: String { device.id }
        public var deviceName: String { device.name }
        public var deviceKind: DeviceKind { device.kind }
        public var memberID: UUID { device.memberID }
    }

    /// Links waiting to be allowed, oldest first.
    public private(set) var pendingLinks: [PendingLink] = []
    let store: LinkedDeviceStore

    @ObservationIgnored private let services: AppServices
    @ObservationIgnored private let link: PeerLink
    /// Sends one message to one device, the link by default. Tests put a phone in memory behind it.
    @ObservationIgnored var transmit: @MainActor (PeerMessage, String) async throws -> Void
    @ObservationIgnored var now: () -> Date = Date.init
    /// How long a request waits for an answer. Tests shorten it.
    @ObservationIgnored var requestLifetime = ApprovalPolicy.requestLifetime
    /// This HomePad's own key, given to linked phones for their photos. Tests use a key in memory.
    @ObservationIgnored lazy var homePadKey: HomePadKey? = HomePadKey.stored()
    /// Asks the iPad's owner for Face ID or the passcode before a link is allowed.
    @ObservationIgnored var verifyOwner: @MainActor (String) async -> Bool = OwnerVerification.verify
    /// Why the last answer was dropped, for tests and logs.
    @ObservationIgnored private(set) var lastRejection: ApprovalLedger.Rejection?
    @ObservationIgnored private var ledger = ApprovalLedger()
    @ObservationIgnored private var waiters: [UUID: Waiter] = [:]
    @ObservationIgnored private let log = Log.make("Approval")

    private struct Waiter {
        let continuation: CheckedContinuation<PersonalDeviceApproval, Never>
        let devices: [String]
        let timeout: Task<Void, Never>
    }

    init(services: AppServices, link: PeerLink) {
        self.services = services
        self.link = link
        self.store = LinkedDeviceStore(settings: services.settings)
        self.transmit = { [weak link] message, peerID in
            guard let link else { throw PeerLinkError.notConnected }
            try await link.send(message, to: peerID)
        }
    }

    func start() {
        pruneLinks()
        link.on(.approvalLink) { [weak self] message, peer in
            guard let body = try? message.content(ApprovalLinkRequest.self) else { return }
            self?.receiveLink(body, from: peer)
        }
        link.on(.approvalStateRequest) { [weak self] _, peer in
            self?.sendState(to: peer.id)
        }
        link.on(.approvalResponse) { [weak self] message, peer in
            guard let response = try? message.content(ApprovalResponse.self) else { return }
            self?.receive(response, from: peer.id)
        }
    }

    // MARK: PersonalDeviceService

    public func approvingDeviceName(for member: HouseholdMember.ID) -> String? {
        let devices = store.devices(for: member).filter(\.canApprove)
        let connected = Set(link.members.filter(\.isConnected).map(\.id))
        return (devices.first { connected.contains($0.id) } ?? devices.first)?.name
    }

    public func requestApproval(for member: HouseholdMember.ID, appID: String, appTitle: String) async -> PersonalDeviceApproval {
        let devices = store.devices(for: member).filter(\.canApprove)
        guard let first = devices.first else { return .unavailable("No personal device is set up for this person.") }
        let request = ApprovalRequest(memberID: member, homePadID: link.identity.deviceID, homePadName: link.identity.name,
                                      appID: appID, appTitle: appTitle, lifetime: requestLifetime)
        guard let message = try? link.message(.approvalRequest, request) else {
            return .unavailable("HomePad could not ask \(first.name).")
        }
        ledger.issue(request, now: now())
        let unreachable = "\(first.name) isn't reachable. Open HomePad on it, then try again."
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                let timeout = Task { [weak self] in
                    try? await Task.sleep(for: .seconds(request.lifetime))
                    guard !Task.isCancelled else { return }
                    self?.finish(request.id, with: .expired)
                }
                waiters[request.id] = Waiter(continuation: continuation, devices: devices.map(\.id), timeout: timeout)
                Task { [weak self] in
                    guard let self else { return }
                    if await self.deliver(message, to: devices.map(\.id)).isEmpty {
                        self.finish(request.id, with: .unavailable(unreachable), tellsDevices: false)
                    }
                }
            }
        } onCancel: {
            Task { @MainActor [weak self] in self?.finish(request.id, with: .unavailable("Cancelled.")) }
        }
    }

    // MARK: Answers

    /// Checks an answer from `deviceID` and ends its request when it counts.
    func receive(_ response: ApprovalResponse, from deviceID: String) {
        switch ledger.verify(response, from: deviceID, devices: store.devices, now: now()) {
        case .approved(let request):
            log.info("Approved on \(deviceID, privacy: .public)")
            finish(request.id, with: .approved)
        case .denied(let request):
            log.info("Denied on \(deviceID, privacy: .public)")
            finish(request.id, with: .denied)
        case .rejected(.expired):
            lastRejection = .expired
            finish(response.requestID, with: .expired)
        case .rejected(let reason):
            lastRejection = reason
            log.info("Dropped an approval answer from \(deviceID, privacy: .public): \(String(describing: reason), privacy: .public)")
        }
    }

    /// Ends a request once, tells its devices to put their prompts away, and
    /// hands the outcome to the gate. A request that reached no device has no
    /// prompt to put away (`tellsDevices` false).
    private func finish(_ id: UUID, with outcome: PersonalDeviceApproval, tellsDevices: Bool = true) {
        guard let waiter = waiters.removeValue(forKey: id) else { return }
        waiter.timeout.cancel()
        ledger.withdraw(id, now: now())
        if tellsDevices, let closed = try? link.message(.approvalClosed, ApprovalClosed(requestID: id)) {
            let devices = waiter.devices
            Task { [weak self] in _ = await self?.deliver(closed, to: devices) }
        }
        waiter.continuation.resume(returning: outcome)
    }

    /// Sends to each device in parallel and returns the IDs that got it.
    private func deliver(_ message: PeerMessage, to ids: [String]) async -> [String] {
        await withTaskGroup(of: String?.self) { group in
            for id in ids {
                group.addTask { @MainActor [weak self] in
                    do {
                        try await self?.transmit(message, id)
                        return id
                    } catch {
                        return nil
                    }
                }
            }
            var delivered: [String] = []
            for await id in group {
                if let id { delivered.append(id) }
            }
            return delivered
        }
    }
}

// MARK: Linking

extension PersonalDeviceApprover {
    /// A phone or Mac asked to approve for a member, or to stop.
    func receiveLink(_ body: ApprovalLinkRequest, from peer: PeerDevice) {
        guard peer.kind.isCompanion else { return }
        let now = now()
        pendingLinks.removeAll { $0.id == peer.id || $0.expiresAt <= now }
        guard let memberID = body.memberID else {
            store.remove(peer.id)
            sendState(to: peer.id)
            return
        }
        guard let member = services.household.members.first(where: { $0.id == memberID }) else {
            sendState(to: peer.id, message: "That person is no longer in the household on \(link.identity.name).")
            return
        }
        guard (try? P256.Signing.PublicKey(rawRepresentation: body.publicKey)) != nil else {
            sendState(to: peer.id, message: "\(link.identity.name) could not read this device's key.")
            return
        }
        let name = body.deviceName.trimmingCharacters(in: .whitespacesAndNewlines).prefix(60)
        var device = LinkedDevice(
            id: peer.id, name: name.isEmpty ? "\(member.name)'s \(peer.kind.displayName)" : String(name), kind: peer.kind,
            memberID: memberID, publicKey: body.publicKey, remoteVersion: body.remoteVersion, linkedAt: now
        )
        if let existing = store.device(peer.id), existing.memberID == memberID, existing.publicKey == body.publicKey {
            // The same key for the same person: nothing new to allow.
            device.linkedAt = existing.linkedAt
            store.save(device)
            sendState(to: peer.id)
            return
        }
        let pending = PendingLink(device: device, expiresAt: now.addingTimeInterval(ApprovalPolicy.linkLifetime))
        pendingLinks.append(pending)
        log.info("\(device.name, privacy: .public) asks to approve unlocks here")
        sendState(to: peer.id)
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(ApprovalPolicy.linkLifetime))
            self?.expire(pending)
        }
        #if DEBUG
        if UserDefaults.standard.bool(forKey: "ConnectAllowLinks") {
            Task { [weak self] in
                try? await Task.sleep(for: .seconds(3))
                self?.save(pending)
            }
        }
        #endif
    }

    /// Someone at this HomePad allowed a link. The member must be recognized
    /// here, or the iPad's owner must pass Face ID or the passcode.
    public func allow(_ pending: PendingLink) async {
        guard pendingLinks.contains(pending) else { return }
        let household = services.household
        let isAtScreen = household.isPersonalContentUnlocked && household.activeMemberID == pending.memberID
        if !isAtScreen {
            let reason = "Let \(pending.deviceName) unlock \(memberName(pending.memberID))'s apps on this HomePad"
            guard await verifyOwner(reason) else { return }
        }
        save(pending)
    }

    /// Someone at this HomePad turned a link down.
    public func decline(_ pending: PendingLink) {
        guard pendingLinks.contains(pending) else { return }
        pendingLinks.removeAll { $0.id == pending.id }
        sendState(to: pending.id, message: "\(link.identity.name) didn't allow it.")
    }

    /// Stops a device approving on this HomePad, from Settings.
    func remove(_ deviceID: String) {
        store.remove(deviceID)
        sendState(to: deviceID)
    }

    /// The name of a member of this household.
    func memberName(_ id: UUID) -> String {
        services.household.members.first { $0.id == id }?.name ?? "Someone"
    }

    /// A person took the household's ID for them as this HomePad joined its
    /// setup: their devices stay linked, and each is told the new ID, since a
    /// device answers only requests for the person it knows it is linked to.
    func moveLinks(from old: UUID, to new: UUID) {
        let moved = store.moveMember(from: old, to: new)
        // The handlers run before the person takes the new ID, and a state
        // names only members of the household, so the states go out after.
        Task { @MainActor [weak self] in
            moved.forEach { self?.sendState(to: $0) }
        }
    }

    /// Drops links to people no longer in the household.
    func pruneLinks() {
        store.prune(keeping: Set(services.household.members.map(\.id)))
    }

    private func save(_ pending: PendingLink) {
        guard pendingLinks.contains(pending) else { return }
        pendingLinks.removeAll { $0.id == pending.id }
        store.save(pending.device)
        sendState(to: pending.id)
    }

    private func expire(_ pending: PendingLink) {
        guard pendingLinks.contains(pending) else { return }
        pendingLinks.removeAll { $0.id == pending.id }
        sendState(to: pending.id, message: "Nobody allowed it on \(link.identity.name) in time.")
    }

    /// What this HomePad holds for one device.
    func state(for deviceID: String, message: String? = nil) -> ApprovalLinkState {
        let members = services.household.members
        let device = store.device(deviceID)
        let isLinked = members.contains { $0.id == device?.memberID }
        return ApprovalLinkState(
            members: members.map(ApprovalMember.init),
            linkedMemberID: isLinked ? device?.memberID : nil,
            pendingMemberID: pendingLinks.first { $0.id == deviceID }?.memberID,
            message: message,
            homePadKey: homePadKey?.publicKey,
            formerMemberIDs: isLinked ? device?.formerMemberIDs : nil
        )
    }

    func sendState(to deviceID: String, message: String? = nil) {
        guard let state = try? link.message(.approvalState, state(for: deviceID, message: message)) else { return }
        Task { [weak self] in try? await self?.transmit(state, deviceID) }
    }
}
