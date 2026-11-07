import Foundation
import HomePadCore
import Observation

/// On a HomePad: visits to the recognized person's own iPhone, for every kind
/// of their data it shares (photos, calendars, reminders).
///
/// A visit starts when a member is recognized here (`household.unlockedMember`)
/// and one of their linked phones shares something. The HomePad wakes that
/// phone over Bluetooth once, opens it on the peer link with one signed
/// challenge, and lets each part fetch what it needs first, in order. Then it
/// tells the phone it needs nothing more. The visit ends, and every part drops
/// what it holds in memory, the moment the person stops being recognized.
@MainActor
@Observable
final class PhoneVisitClient {
    /// Linked phones that share something, by device ID.
    private(set) var sharedPhones: [String: SharedPhone]

    @ObservationIgnored let services: AppServices
    @ObservationIgnored let link: PeerLink
    @ObservationIgnored let approver: PersonalDeviceApprover
    /// The kinds a visit carries, in the order their first fetch runs.
    @ObservationIgnored private(set) var parts: [any PhoneVisitPart] = []
    /// Sends to a phone on whatever session is open, dialing if needed.
    @ObservationIgnored var transmit: @MainActor (PeerMessage, String) async throws -> Void
    /// Sends on one session only, the one the phone opened on.
    @ObservationIgnored var transmitOnSession: @MainActor (PeerMessage, String, UUID) throws -> Void
    /// The session open with a device now, if any.
    @ObservationIgnored var currentSession: @MainActor (String) -> UUID?
    /// Wakes phones over Bluetooth. Nil until some phone shares.
    @ObservationIgnored var waker: (any PhoneWaking)?
    @ObservationIgnored var makeWaker: @MainActor () -> any PhoneWaking = { HomePadWakeBeacon() }
    @ObservationIgnored var now: () -> Date = Date.init
    /// How long to wait for the phone to open, and for each answer.
    @ObservationIgnored var openTimeout: TimeInterval = 12
    @ObservationIgnored var replyTimeout: TimeInterval = 15
    @ObservationIgnored private(set) var visit: PhoneVisit?
    @ObservationIgnored let log = Log.make("PhoneVisit")

    init(services: AppServices, link: PeerLink, approver: PersonalDeviceApprover) {
        self.services = services
        self.link = link
        self.approver = approver
        self.sharedPhones = services.settings[SharedPhones.key]
        self.transmit = { [weak link] message, peerID in
            guard let link else { throw PeerLinkError.notConnected }
            try await link.send(message, to: peerID)
        }
        self.transmitOnSession = { [weak link] message, peerID, session in
            guard let link else { throw PeerLinkError.notConnected }
            try link.send(message, to: peerID, onSession: session)
        }
        self.currentSession = { [weak link] peerID in link?.sessionID(with: peerID) }
    }

    /// Adds a kind of data. The first fetches run in the order parts are added.
    func add(_ part: any PhoneVisitPart) {
        parts.append(part)
    }

    func start() {
        registerHandlers()
        householdChanged()
        observeHousehold()
    }

    /// The visit to `member`, while it is on.
    func visit(of member: UUID) -> PhoneVisit? {
        visit?.memberID == member ? visit : nil
    }

    /// True when `visit` is the one on now.
    func isCurrent(_ visit: PhoneVisit) -> Bool {
        self.visit === visit
    }

    /// True while the visit's phone is on the peer link.
    func isConnected(_ visit: PhoneVisit) -> Bool {
        currentSession(visit.deviceID) != nil
    }

    // MARK: Visits

    /// Starts or ends a visit to match who is recognized here and what their phones share.
    func evaluate() {
        let member = services.household.unlockedMember?.id
        let connected = Set(link.members.filter(\.isConnected).map(\.id))
        let deviceID = member.flatMap { SharedPhones.phone(for: $0, in: sharedPhones, connected: connected) }
        let record = deviceID.flatMap { sharedPhones[$0] }
        if let visit, visit.memberID == member, visit.deviceID == deviceID, visit.kinds == record?.kinds { return }
        endVisit()
        guard let member, let deviceID, let record, let device = approver.store.device(deviceID) else { return }
        let visit = PhoneVisit(memberID: member, deviceID: deviceID, deviceName: device.name,
                               wakeTag: record.wakeTag, kinds: record.kinds)
        self.visit = visit
        log.info("Visit started, asking \(device.name, privacy: .public) for \(PhoneDataKind.names(record.kinds).joined(separator: ", "), privacy: .public)")
        parts(for: visit.kinds).forEach { $0.visitStarted(visit) }
        Task { await run(visit) }
    }

    /// Ends the visit: nothing of the person stays in memory, and the phone
    /// hears that the HomePad needs nothing more.
    func endVisit() {
        guard let visit else { return }
        self.visit = nil
        if let session = visit.grantedSession, let close = try? link.message(.visitClose, PhoneVisitClose()) {
            try? transmitOnSession(close, visit.deviceID, session)
        }
        visit.finish()
        parts(for: visit.kinds).forEach { $0.visitEnded(visit) }
        log.info("Visit ended")
    }

    /// One wake and one challenge for every kind, then each part's first
    /// fetch in order, then the session closes once nothing waits on it.
    func run(_ visit: PhoneVisit) async {
        guard await open(visit), isCurrent(visit) else { return }
        for part in parts(for: visit.grantedKinds) {
            await part.prefetch(visit)
            guard isCurrent(visit) else { return }
        }
        visit.hasFetched = true
        closeIfIdle(visit)
    }

    /// Lets each part show the visit as it stands.
    func publish(_ visit: PhoneVisit) {
        guard isCurrent(visit) else { return }
        parts(for: visit.kinds).forEach { $0.publish(visit) }
    }

    /// The parts that carry any of `kinds`.
    func parts(for kinds: Set<PhoneDataKind>) -> [any PhoneVisitPart] {
        parts.filter { !$0.kinds.isDisjoint(with: kinds) }
    }

    // MARK: Sharing

    /// A linked phone shares, or stops sharing, some kinds. `kinds` is all
    /// the offer speaks for, and `sharing` the ones it shares of them. A
    /// person who stops sharing a kind leaves nothing of it on this iPad.
    func receiveOffer(from peer: PeerDevice, sharing: Set<PhoneDataKind>, of kinds: Set<PhoneDataKind>, wakeTag: Data?) {
        guard peer.kind.isCompanion, let device = approver.store.device(peer.id) else { return }
        var phones = sharedPhones
        var record = phones[peer.id] ?? SharedPhone(memberID: device.memberID, wakeTag: Data(), kinds: [])
        record.memberID = device.memberID
        record.kinds.subtract(kinds)
        if let tag = wakeTag, tag.count == ProximityWake.tagLength {
            record.kinds.formUnion(sharing)
            record.wakeTag = tag
        }
        phones[peer.id] = record.kinds.isEmpty || record.wakeTag.count != ProximityWake.tagLength ? nil : record
        guard phones != sharedPhones else { return }
        apply(phones)
        log.info("\(device.name, privacy: .public) shares \(PhoneDataKind.names(phones[peer.id]?.kinds ?? []).joined(separator: ", "), privacy: .public)")
        evaluate()
    }

    /// Saves the records and forgets, kind by kind, what members no longer share.
    private func apply(_ phones: [String: SharedPhone]) {
        let before = SharedPhones.kindsByMember(sharedPhones)
        let after = SharedPhones.kindsByMember(phones)
        setSharedPhones(phones)
        for (member, kinds) in before {
            let still = after[member] ?? []
            let lost = kinds.subtracting(still)
            guard !lost.isEmpty else { continue }
            parts(for: lost).forEach { $0.forget(member, keeping: still.intersection($0.kinds)) }
        }
    }

    func setSharedPhones(_ phones: [String: SharedPhone]) {
        sharedPhones = phones
        services.settings[SharedPhones.key] = phones
        if phones.isEmpty {
            waker?.stop()
            waker = nil
        } else if waker == nil {
            let waker = makeWaker()
            waker.start()
            self.waker = waker
        }
    }

    /// A person took the household's ID for them as this HomePad joined its
    /// setup: their phones keep sharing under it. What is saved under the old
    /// ID is pruned with the next household change and fills again on a visit.
    func moveMember(from old: UUID, to new: UUID) {
        var phones = sharedPhones
        for (id, record) in phones where record.memberID == old {
            phones[id]?.memberID = new
        }
        guard phones != sharedPhones else { return }
        setSharedPhones(phones)
    }

    // MARK: Household

    /// Watches who is recognized, who is in the household and which phones are linked.
    private func observeHousehold() {
        withObservationTracking {
            _ = services.household.unlockedMember?.id
            _ = services.household.members.map(\.id)
            _ = approver.store.devices
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.householdChanged()
                self?.observeHousehold()
            }
        }
    }

    /// Forgets phones and caches of people no longer linked or in the household.
    func householdChanged() {
        let members = Set(services.household.members.map(\.id))
        let valid = SharedPhones.valid(sharedPhones, linked: approver.store.devices, members: members)
        if valid != sharedPhones { apply(valid) }
        let kept = SharedPhones.kindsByMember(valid)
        for part in parts {
            part.prune(keeping: Set(kept.filter { !$0.value.isDisjoint(with: part.kinds) }.keys))
        }
        evaluate()
    }
}

/// On a HomePad: wakes phones over Bluetooth.
@MainActor
protocol PhoneWaking: AnyObject {
    func start()
    func stop()
    /// Wakes the phone that wrote `tag`. False when it is not connected over Bluetooth.
    @discardableResult func wake(_ tag: Data) -> Bool
}

extension HomePadWakeBeacon: PhoneWaking {}
