import Foundation
import HomePadCore
import Observation

/// On a HomePad: each member's own Apple Music, linked from their iPhone.
/// Installed as `services.memberMusic`, which the Music app reads.
///
/// A token is taken only from a phone linked to that member here (Use
/// Personal Device), only after this HomePad proved itself to the phone with
/// its own key, and only on the session that proof went out on. Tokens live in
/// this iPad's Keychain, one item per member, never synced and never restored
/// to another device. They are deleted when the person turns sharing off on
/// their phone, when that phone stops being linked to them, and when they
/// leave the household. They move with the person when this HomePad joins a
/// household's setup and the person takes the household's ID.
@MainActor
@Observable
public final class AppleMusicLinks: MemberMusicService {
    public private(set) var links: [UUID: MemberMusicLink]

    @ObservationIgnored private let services: AppServices
    @ObservationIgnored private let link: PeerLink
    @ObservationIgnored private let approver: PersonalDeviceApprover
    /// Where the tokens are kept. Tests keep them in memory.
    @ObservationIgnored var secrets: any SecretStore = KeychainStore(
        service: "com.ksha23.homepad.music.tokens", synchronizable: false, thisDeviceOnly: true
    )
    /// Answers on the session a message came in on. Tests keep it in memory.
    @ObservationIgnored var reply: @MainActor (PeerMessage, PeerDevice) throws -> Void
    /// Sends to a device on whatever session is open.
    @ObservationIgnored var transmit: @MainActor (PeerMessage, String) async throws -> Void
    @ObservationIgnored var now: () -> Date = Date.init
    @ObservationIgnored private var book = AppleMusicProofBook()
    @ObservationIgnored private let log = Log.make("AppleMusicLinks")

    /// The links by member ID, nothing secret.
    static let linksKey = SettingKey<[String: MemberMusicLink]>("connect.music.links", default: [:])

    init(services: AppServices, link: PeerLink, approver: PersonalDeviceApprover) {
        self.services = services
        self.link = link
        self.approver = approver
        self.links = Dictionary(uniqueKeysWithValues: services.settings[Self.linksKey].compactMap { key, value in
            UUID(uuidString: key).map { ($0, value) }
        })
        self.reply = { [weak link] message, peer in
            guard let link, let session = peer.sessionID else { throw PeerLinkError.notConnected }
            try link.send(message, to: peer.id, onSession: session)
        }
        self.transmit = { [weak link] message, peerID in
            guard let link else { throw PeerLinkError.notConnected }
            try await link.send(message, to: peerID)
        }
    }

    func start() {
        link.on(.musicShare) { [weak self] message, peer in
            guard let request = try? message.content(MusicShareRequest.self) else { return }
            self?.receive(request, from: peer)
        }
        link.on(.musicToken) { [weak self] message, peer in
            guard let handoff = try? message.content(MusicTokenHandoff.self) else { return }
            self?.receive(handoff, from: peer)
        }
        link.on(.musicUnlink) { [weak self] message, peer in
            guard let unlink = try? message.content(MusicUnlink.self) else { return }
            self?.receive(unlink, from: peer)
        }
        link.on(.musicStateRequest) { [weak self] _, peer in
            guard peer.kind.isCompanion else { return }
            self?.send(.musicState, self?.state(for: peer.id), to: peer)
        }
        link.onDisconnect { [weak self] peerID in self?.book.revoke(peerID: peerID) }
        householdChanged()
        observeHousehold()
    }

    // MARK: MemberMusicService

    public func userToken(for member: UUID) -> String? {
        guard links[member] != nil else { return nil }
        return secrets.string(for: Self.account(member))
    }

    public func tokenRejected(for member: UUID) {
        guard var record = links[member], !record.needsNewToken else { return }
        secrets.set(nil, for: Self.account(member))
        record.needsNewToken = true
        links[member] = record
        persist()
        log.info("Apple Music turned down a member's token. Asking their phone for a new one.")
        // Phones that are not reachable now hear it when they next ask.
        for device in approver.store.devices(for: member) {
            guard let message = try? link.message(.musicState, state(for: device.id)) else { continue }
            Task { [weak self] in try? await self?.transmit(message, device.id) }
        }
    }

    // MARK: Messages

    /// A linked phone asks this HomePad to prove itself. It signs only for the
    /// member that phone is linked to here.
    func receive(_ request: MusicShareRequest, from peer: PeerDevice) {
        guard peer.kind.isCompanion, let sessionID = peer.sessionID else { return }
        let session = AppleMusicProofBook.Session(peerID: peer.id, sessionID: sessionID)
        let isMember = services.household.members.contains { $0.id == request.memberID }
        let linked = approver.store.device(peer.id)?.memberID
        if case .failure(let reason) = book.issue(request, on: session, linkedMemberID: linked, isMember: isMember, now: now()) {
            return refuse(reason, request: request.requestID, to: peer)
        }
        let bytes = MusicShareProof.signedBytes(requestID: request.requestID, nonce: request.nonce, memberID: request.memberID,
                                                homePadID: link.identity.deviceID, phoneID: peer.id)
        guard let key = approver.homePadKey, let signature = try? key.sign(bytes) else {
            return refuse(.notVerified, request: request.requestID, to: peer)
        }
        send(.musicProof, MusicShareProof(requestID: request.requestID, signature: signature), to: peer)
    }

    /// The token that follows a proof. Kept only on the proof's session, for its member.
    func receive(_ handoff: MusicTokenHandoff, from peer: PeerDevice) {
        guard peer.kind.isCompanion, let sessionID = peer.sessionID else { return }
        let session = AppleMusicProofBook.Session(peerID: peer.id, sessionID: sessionID)
        let device = approver.store.device(peer.id)
        switch book.accept(handoff, on: session, linkedMemberID: device?.memberID, now: now()) {
        case .success(let member):
            guard let device, secrets.set(handoff.userToken, for: Self.account(member)) else {
                return refuse(.badToken, request: handoff.requestID, to: peer)
            }
            links[member] = MemberMusicLink(deviceID: peer.id, deviceName: device.name, linkedAt: now())
            persist()
            log.info("\(device.name, privacy: .public) linked its owner's Apple Music")
            send(.musicState, state(for: peer.id, requestID: handoff.requestID), to: peer)
        case .failure(let reason):
            log.info("Did not take an Apple Music token from \(peer.name, privacy: .public): \(reason.rawValue, privacy: .public)")
            refuse(reason, request: handoff.requestID, to: peer)
        }
    }

    /// The person turned sharing off on their phone. Any phone linked to that
    /// member here may turn it off.
    func receive(_ unlink: MusicUnlink, from peer: PeerDevice) {
        guard peer.kind.isCompanion else { return }
        if approver.store.device(peer.id)?.memberID == unlink.memberID, links[unlink.memberID] != nil {
            forget(unlink.memberID)
            log.info("\(peer.name, privacy: .public) unlinked its owner's Apple Music")
        }
        send(.musicState, state(for: peer.id), to: peer)
    }

    /// What this HomePad holds for one device.
    func state(for deviceID: String, requestID: UUID? = nil, message: String? = nil) -> MusicLinkState {
        let member = approver.store.device(deviceID)?.memberID
        let record = member.flatMap { links[$0] }
        let hasToken = member.map { secrets.string(for: Self.account($0)) != nil } ?? false
        return MusicLinkState(memberID: member, isLinked: record != nil && hasToken,
                              needsToken: record != nil && (record?.needsNewToken == true || !hasToken),
                              requestID: requestID, message: message)
    }

    // MARK: Household

    /// Forgets the tokens of people who left the household, and of people
    /// whose phone that sent the token is no longer linked to them.
    func householdChanged() {
        let members = Set(services.household.members.map(\.id))
        for (member, record) in links {
            let stillLinked = approver.store.device(record.deviceID)?.memberID == member
            guard !members.contains(member) || !stillLinked else { continue }
            forget(member)
            log.info("Forgot a member's Apple Music: \(members.contains(member) ? "their phone was unlinked" : "they left the household", privacy: .public)")
        }
    }

    /// A person took the household's ID for them as this HomePad joined its
    /// setup: their token and link move to it, so Apple Music stays theirs here.
    /// Their phone hears the old ID with its approval state and keeps sharing.
    func moveMember(from old: UUID, to new: UUID) {
        guard let record = links[old], links[new] == nil else { return }
        let token = secrets.string(for: Self.account(old))
        secrets.set(nil, for: Self.account(old))
        links[old] = nil
        if let token, !secrets.set(token, for: Self.account(new)) {
            log.info("Could not keep a member's Apple Music token under their new ID")
        }
        links[new] = record
        persist()
    }

    private func observeHousehold() {
        withObservationTracking {
            _ = services.household.members.map(\.id)
            _ = approver.store.devices
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.householdChanged()
                self?.observeHousehold()
            }
        }
    }

    // MARK: Plumbing

    private func forget(_ member: UUID) {
        secrets.set(nil, for: Self.account(member))
        links[member] = nil
        persist()
    }

    private func persist() {
        services.settings[Self.linksKey] = Dictionary(uniqueKeysWithValues: links.map { ($0.key.uuidString, $0.value) })
    }

    private static func account(_ member: UUID) -> String { "token.\(member.uuidString)" }

    private func refuse(_ reason: MusicShareRefusal, request: UUID, to peer: PeerDevice) {
        send(.musicState, state(for: peer.id, requestID: request, message: explanation(reason, for: peer)), to: peer)
    }

    private func explanation(_ reason: MusicShareRefusal, for peer: PeerDevice) -> String {
        let name = link.identity.name
        switch reason {
        case .notLinked: return "This \(peer.kind.displayName) isn't linked to that person on \(name). Link it under Unlock With This \(peer.kind.displayName) first."
        case .notMember: return "That person is no longer in the household on \(name)."
        case .expired: return "\(name) didn't get your Apple Music in time. Try again."
        case .notVerified: return "\(name) couldn't prove it is the HomePad you linked to."
        case .badToken: return "\(name) couldn't keep your Apple Music token. Try again."
        }
    }

    private func send<Content: Encodable>(_ type: PeerMessageType, _ content: Content?, to peer: PeerDevice) {
        guard let content, let message = try? link.message(type, content) else { return }
        do {
            try reply(message, peer)
        } catch {
            log.info("Could not answer \(peer.name, privacy: .public): \(error.localizedDescription, privacy: .public)")
        }
    }
}
