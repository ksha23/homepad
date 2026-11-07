import Foundation
import HomePadCore

/// On a HomePad: takes a Spotify sign-in made on a member's own iPhone and
/// keeps it for that member only, and tells each linked phone where its
/// member's Spotify stands here.
///
/// The phone must be linked to the member here (Unlock With This iPhone), and
/// the handoff must pass `SpotifyHandoffBook`. The Audio module's media
/// service then exchanges the code for tokens and keeps the refresh token in
/// this iPad's Keychain (`SpotifyMemberAccounts`). Nothing about the sign-in
/// is logged but its outcome.
@MainActor
final class SpotifyHandoffReceiver {
    private let services: AppServices
    private let link: PeerLink
    private let approver: PersonalDeviceApprover
    /// Answers on the session a message came in on. Tests keep it in memory.
    var reply: @MainActor (PeerMessage, PeerDevice) throws -> Void
    var now: () -> Date = Date.init
    /// Where members' Spotify accounts are kept: the Audio module's media service.
    var accounts: @MainActor () -> (any SpotifyMemberAccounts)?
    private var book = SpotifyHandoffBook()
    private let log = Log.make("SpotifyHandoff")

    init(services: AppServices, link: PeerLink, approver: PersonalDeviceApprover) {
        self.services = services
        self.link = link
        self.approver = approver
        self.reply = { [weak link] message, peer in
            guard let link, let session = peer.sessionID else { throw PeerLinkError.notConnected }
            try link.send(message, to: peer.id, onSession: session)
        }
        self.accounts = { [weak services] in services?.media as? any SpotifyMemberAccounts }
    }

    func start() {
        link.on(.spotifyStateRequest) { [weak self] _, peer in
            self?.sendState(to: peer)
        }
        link.on(.spotifyHello) { [weak self] message, peer in
            guard let hello = try? message.content(SpotifyHello.self) else { return }
            self?.receive(hello, from: peer)
        }
        link.on(.spotifyHandoff) { [weak self] message, peer in
            guard let handoff = try? message.content(SpotifyHandoff.self) else { return }
            Task { await self?.receive(handoff, from: peer) }
        }
        link.on(.spotifySignOut) { [weak self] message, peer in
            guard let body = try? message.content(SpotifySignOut.self) else { return }
            self?.receive(body, from: peer)
        }
        link.onDisconnect { [weak self] peerID in
            self?.book.revoke(peerID: peerID)
        }
    }

    // MARK: State

    /// What this HomePad holds for one device's member.
    func state(for deviceID: String) -> SpotifyStateReply {
        guard let device = linkedDevice(deviceID) else { return SpotifyStateReply(isLinked: false, account: nil) }
        return SpotifyStateReply(isLinked: true, account: accounts()?.spotifyAccount(for: device.memberID))
    }

    func sendState(to peer: PeerDevice) {
        send(.spotifyState, state(for: peer.id), to: peer)
    }

    /// The link of a device to someone still in the household.
    private func linkedDevice(_ deviceID: String) -> LinkedDevice? {
        guard let device = approver.store.device(deviceID),
              services.household.members.contains(where: { $0.id == device.memberID }) else { return nil }
        return device
    }

    // MARK: Handing over

    func receive(_ hello: SpotifyHello, from peer: PeerDevice) {
        guard let sessionID = peer.sessionID else { return }
        guard accounts()?.spotifyAccount(for: hello.memberID).isSetUp == true else {
            return refuse(hello.requestID, .notSetUp, to: peer)
        }
        guard let key = approver.homePadKey else { return refuse(hello.requestID, .notVerified, to: peer) }
        let session = SpotifyHandoffBook.Session(peerID: peer.id, sessionID: sessionID)
        switch book.hello(hello, on: session, linked: linkedDevice(peer.id), homePadID: link.identity.deviceID,
                          sign: key.sign, now: now()) {
        case .success(let challenge):
            send(.spotifyChallenge, challenge, to: peer)
        case .failure(let reason):
            refuse(hello.requestID, reason, to: peer)
        }
    }

    func receive(_ handoff: SpotifyHandoff, from peer: PeerDevice) async {
        guard let sessionID = peer.sessionID else { return }
        let session = SpotifyHandoffBook.Session(peerID: peer.id, sessionID: sessionID)
        let device = linkedDevice(peer.id)
        switch book.handoff(handoff, on: session, linked: device, homePadID: link.identity.deviceID, now: now()) {
        case .failure(let reason):
            refuse(handoff.requestID, reason, to: peer)
        case .success(let (member, signIn)):
            guard let accounts = accounts() else { return refuse(handoff.requestID, .notSetUp, to: peer) }
            let deviceName = device?.name ?? peer.name
            do {
                let account = try await accounts.linkSpotify(code: signIn.code, verifier: signIn.verifier, for: member, from: deviceName)
                log.info("Linked a Spotify account from \(deviceName, privacy: .public)")
                send(.spotifyResult, SpotifyResult(requestID: handoff.requestID, account: account), to: peer)
            } catch {
                log.info("A Spotify sign-in from \(deviceName, privacy: .public) did not link: \(error.localizedDescription, privacy: .public)")
                let result = SpotifyResult(requestID: handoff.requestID, account: accounts.spotifyAccount(for: member),
                                           error: error.localizedDescription)
                send(.spotifyResult, result, to: peer)
            }
        }
    }

    /// Signs a member's Spotify out here, asked by the phone linked to them.
    func receive(_ body: SpotifySignOut, from peer: PeerDevice) {
        guard linkedDevice(peer.id)?.memberID == body.memberID else {
            log.info("Ignored a Spotify sign-out from \(peer.name, privacy: .public), which is not linked to that person")
            return
        }
        accounts()?.signOutSpotify(for: body.memberID)
        sendState(to: peer)
    }

    // MARK: Plumbing

    private func refuse(_ requestID: UUID, _ reason: SpotifyRefusal, to peer: PeerDevice) {
        log.info("Refused a Spotify sign-in from \(peer.name, privacy: .public): \(reason.rawValue, privacy: .public)")
        send(.spotifyRefused, SpotifyRefused(requestID: requestID, reason: reason), to: peer)
    }

    private func send(_ type: PeerMessageType, _ body: some Encodable, to peer: PeerDevice) {
        do {
            try reply(try link.message(type, body), peer)
        } catch {
            log.info("Could not answer \(peer.name, privacy: .public): \(error.localizedDescription, privacy: .public)")
        }
    }
}
