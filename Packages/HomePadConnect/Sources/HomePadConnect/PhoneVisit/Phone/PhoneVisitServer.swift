import Foundation
import HomePadCore
import Observation

/// On an iPhone: opens visits from the HomePads its owner shares with, for
/// the kinds they share with each (photos, calendars, reminders), and to
/// nothing else.
///
/// A HomePad gets a kind only on a session it opened with `PhoneGrantBook`:
/// the phone is linked to the member it asks for, the person shares that
/// kind with that HomePad, HomePad on this phone may read it, and the HomePad
/// signed a fresh challenge with the key the phone kept when it linked. Each
/// part checks the grant again for every request, and every answer goes back
/// on the session the request came in on. One Bluetooth listener wakes the
/// app for every kind.
@MainActor
@Observable
public final class PhoneVisitServer {
    @ObservationIgnored let services: AppServices
    @ObservationIgnored let link: PeerLink
    @ObservationIgnored let approvals: ApprovalResponder
    /// The kinds this phone can share, each with its own choices.
    @ObservationIgnored private(set) var parts: [any PhoneVisitServing] = []
    /// Answers on the session a request came in on. Tests keep it in memory.
    @ObservationIgnored var reply: @MainActor (PeerMessage, PeerDevice) throws -> Void
    /// Sends an offer to a HomePad on whatever session is open.
    @ObservationIgnored var transmit: @MainActor (PeerMessage, String) async throws -> Void
    @ObservationIgnored var now: () -> Date = Date.init
    /// Keeps the app running a little while it answers in the background.
    @ObservationIgnored var window: any BackgroundWindow = AppBackgroundWindow()
    /// The Bluetooth listener that wakes this app. Made only once someone shares.
    @ObservationIgnored var wakeListener: (any WakeListening)?
    @ObservationIgnored var makeWakeListener: @MainActor () -> any WakeListening = { PhoneWakeListener() }
    @ObservationIgnored private var book = PhoneGrantBook()
    @ObservationIgnored private let log = Log.make("PhoneVisit")
    /// Bumped when the wake listener comes or goes, so the cards redraw.
    private var listenerRevision = 0

    static let homePadKeysKey = SettingKey<[String: Data]>("connect.photos.homePadKeys", default: [:])

    init(services: AppServices, link: PeerLink, approvals: ApprovalResponder) {
        self.services = services
        self.link = link
        self.approvals = approvals
        self.reply = { [weak link] message, peer in
            guard let link, let session = peer.sessionID else { throw PeerLinkError.notConnected }
            try link.send(message, to: peer.id, onSession: session)
        }
        self.transmit = { [weak link] message, peerID in
            guard let link else { throw PeerLinkError.notConnected }
            try await link.send(message, to: peerID)
        }
    }

    /// Adds a kind of data this phone can share.
    func add(_ part: any PhoneVisitServing) {
        parts.append(part)
    }

    func start() {
        link.on(.approvalState) { [weak self] message, peer in
            guard peer.kind == .homePad, let state = try? message.content(ApprovalLinkState.self) else { return }
            self?.noteLinkState(state, from: peer.id)
        }
        link.on(.visitHello) { [weak self] message, peer in
            guard let hello = try? message.content(PhoneVisitHello.self) else { return }
            self?.receive(hello, from: peer)
        }
        link.on(.visitOpen) { [weak self] message, peer in
            guard let open = try? message.content(PhoneVisitOpen.self) else { return }
            self?.receive(open, from: peer)
        }
        link.on(.visitClose) { [weak self] _, peer in
            self?.close(peer)
        }
        link.onConnect { [weak self] peer in
            guard peer.kind == .homePad, let self else { return }
            for part in parts { Task { await part.sendOffer(to: peer.id) } }
        }
        link.onDisconnect { [weak self] peerID in
            self?.book.revoke(peerID: peerID)
            self?.endWindowIfIdle()
        }
        updateWakeListener()
    }

    // MARK: Sharing

    /// The member this phone is linked to on that HomePad.
    func linkedMember(on homePadID: String) -> UUID? {
        approvals.linkedMember(on: homePadID)
    }

    /// The tag this phone writes over Bluetooth for that HomePad: the one a
    /// kind already shares with, or a new random one. One tag per HomePad, so
    /// the HomePad wakes this phone the same way for every kind.
    func wakeTag(for homePadID: String) -> Data {
        parts.lazy.compactMap { $0.wakeTag(for: homePadID) }.first ?? Data(ApprovalRequest.randomNonce().prefix(ProximityWake.tagLength))
    }

    /// A part's sharing changed for one HomePad: tell it, stop what it may no
    /// longer read, and keep Bluetooth only while something is shared.
    func sharingChanged(_ part: any PhoneVisitServing, with homePadID: String) async {
        let shared = part.sharedKinds(with: homePadID)
        for kind in part.kinds.subtracting(shared) { book.revoke(kind, peerID: homePadID) }
        await part.sendOffer(to: homePadID)
        updateWakeListener()
    }

    /// Why the HomePad cannot wake this phone over Bluetooth, nil while
    /// nothing is shared or all is well.
    public var wakeProblem: String? {
        _ = listenerRevision
        return wakeListener?.problem
    }

    // MARK: Link state

    /// Keeps the HomePad's key the first time the phone sees it linked, and
    /// forgets it, and stops sharing everything, once the phone is no longer linked there.
    func noteLinkState(_ state: ApprovalLinkState, from homePadID: String) {
        var keys = services.settings[Self.homePadKeysKey]
        if state.linkedMemberID == nil {
            let shares = parts.contains { !$0.sharedKinds(with: homePadID).isEmpty }
            guard keys[homePadID] != nil || shares else { return }
            keys[homePadID] = nil
            services.settings[Self.homePadKeysKey] = keys
            parts.forEach { $0.stopSharing(with: homePadID) }
            book.revoke(peerID: homePadID)
            updateWakeListener()
            return
        }
        // Kept from the first time only. A HomePad that later shows another
        // key gets nothing until the person links again.
        if keys[homePadID] == nil, let key = state.homePadKey {
            keys[homePadID] = key
            services.settings[Self.homePadKeysKey] = keys
        }
    }

    // MARK: Opening

    func receive(_ hello: PhoneVisitHello, from peer: PeerDevice) {
        guard peer.kind == .homePad, let sessionID = peer.sessionID else { return }
        window.begin()
        let session = PhoneGrantBook.Session(peerID: peer.id, sessionID: sessionID)
        switch book.hello(hello, on: session, trust: trust(for: peer.id), now: now()) {
        case .success(let challenge):
            send(.visitChallenge, challenge, to: peer)
        case .failure(let reason):
            log.info("Refused a visit from \(peer.name, privacy: .public): \(reason.rawValue, privacy: .public)")
            send(.visitRefused, PhoneVisitRefused(requestID: hello.requestID, reason: reason), to: peer)
            endWindowIfIdle()
        }
    }

    func receive(_ open: PhoneVisitOpen, from peer: PeerDevice) {
        guard peer.kind == .homePad, let sessionID = peer.sessionID else { return }
        let session = PhoneGrantBook.Session(peerID: peer.id, sessionID: sessionID)
        switch book.open(open, on: session, phoneID: link.identity.deviceID, trust: trust(for: peer.id), now: now()) {
        case .success(let kinds):
            log.info("Opened \(PhoneDataKind.names(kinds).joined(separator: ", "), privacy: .public) to \(peer.name, privacy: .public)")
            send(.visitOpened, PhoneVisitOpened(requestID: open.requestID, kinds: PhoneDataKind.names(kinds)), to: peer)
        case .failure(let reason):
            log.info("Did not open to \(peer.name, privacy: .public): \(reason.rawValue, privacy: .public)")
            send(.visitRefused, PhoneVisitRefused(requestID: open.requestID, reason: reason), to: peer)
            endWindowIfIdle()
        }
    }

    /// The member whose `kind` this request may read, checked again for every
    /// request: the session's grant covers it, the phone is still linked to
    /// that member there, and the person still shares it. Nil means drop it.
    func grantedMember(_ peer: PeerDevice, for kind: PhoneDataKind) -> UUID? {
        guard let sessionID = peer.sessionID else { return nil }
        let session = PhoneGrantBook.Session(peerID: peer.id, sessionID: sessionID)
        guard let member = book.grantedMember(session, kind: kind, now: now()), linkedMember(on: peer.id) == member,
              parts.contains(where: { $0.sharedKinds(with: peer.id).contains(kind) }) else {
            log.info("Dropped a \(kind.rawValue, privacy: .public) request from \(peer.name, privacy: .public) without an open session")
            return nil
        }
        return member
    }

    /// True while the request's session may still read `kind` of `member`,
    /// for answers sent one by one.
    func isGranted(_ peer: PeerDevice, member: UUID, kind: PhoneDataKind) -> Bool {
        guard let sessionID = peer.sessionID else { return false }
        return book.isGranted(PhoneGrantBook.Session(peerID: peer.id, sessionID: sessionID), memberID: member, kind: kind, now: now())
    }

    func close(_ peer: PeerDevice) {
        guard let sessionID = peer.sessionID else { return }
        book.close(PhoneGrantBook.Session(peerID: peer.id, sessionID: sessionID))
        endWindowIfIdle()
    }

    /// The Bluetooth listener woke the app: find the HomePads again and wait
    /// for them to ask, inside the short time iOS gives a woken app.
    func wakeReceived() {
        guard !allWakeTags.isEmpty else { return }
        log.info("Woken by a HomePad nearby")
        window.begin()
        if window.isInBackground { link.restart() }
    }

    // MARK: Plumbing

    private func trust(for homePadID: String) -> PhoneGrantBook.HomePadTrust {
        PhoneGrantBook.HomePadTrust(
            linkedMemberID: linkedMember(on: homePadID),
            sharing: parts.reduce(into: []) { $0.formUnion($1.sharedKinds(with: homePadID)) },
            readable: parts.reduce(into: []) { $0.formUnion($1.readableKinds) },
            homePadKey: services.settings[Self.homePadKeysKey][homePadID]
        )
    }

    /// Answers a HomePad on the session its request came in on.
    func send<Content: Encodable>(_ type: PeerMessageType, _ content: Content, attachment: Data? = nil, to peer: PeerDevice) {
        do {
            try reply(try link.message(type, content, attachment: attachment), peer)
        } catch {
            log.info("Could not answer \(peer.name, privacy: .public): \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Sends an offer on whatever session is open with that HomePad.
    func sendOffer<Content: Encodable>(_ type: PeerMessageType, _ offer: Content, to homePadID: String) async {
        guard let message = try? link.message(type, offer) else { return }
        try? await transmit(message, homePadID)
    }

    func endWindowIfIdle() {
        if !book.hasOpenGrants(now: now()) { window.end() }
    }

    private var allWakeTags: [Data] {
        Array(Set(parts.flatMap(\.wakeTags))).sorted { $0.lexicographicallyPrecedes($1) }
    }

    /// Bluetooth runs only while the person shares something with some
    /// HomePad, so nobody is asked for Bluetooth who never turned this on.
    func updateWakeListener() {
        let tags = allWakeTags
        if tags.isEmpty {
            wakeListener?.stop()
            wakeListener = nil
            listenerRevision += 1
            return
        }
        if wakeListener == nil {
            let listener = makeWakeListener()
            listener.onWake = { [weak self] in self?.wakeReceived() }
            wakeListener = listener
            listenerRevision += 1
        }
        wakeListener?.listen(tags: tags)
    }
}

/// On a phone: one kind of its owner's data it can share with HomePads, with
/// the person's choices for each HomePad.
@MainActor
protocol PhoneVisitServing: AnyObject {
    /// The kinds this part serves.
    var kinds: Set<PhoneDataKind> { get }
    /// The kinds the person shares with that HomePad right now.
    func sharedKinds(with homePadID: String) -> Set<PhoneDataKind>
    /// The kinds HomePad on this phone may read right now.
    var readableKinds: Set<PhoneDataKind> { get }
    /// The wake tag kept with this part's choice for that HomePad, if any.
    func wakeTag(for homePadID: String) -> Data?
    /// Every wake tag this part keeps.
    var wakeTags: [Data] { get }
    /// Tells that HomePad what this phone shares, after it connects or a choice changes.
    func sendOffer(to homePadID: String) async
    /// The phone is no longer linked there: stop sharing and keep nothing.
    func stopSharing(with homePadID: String)
}
