import CryptoKit
import Foundation
import HomePadCore
import Observation

/// On an iPhone: shares its owner's Apple Music with the HomePads they turned
/// it on for, so those HomePads show their library while they recognize them.
///
/// What leaves the phone is a Music User Token, never the Apple Account. It
/// goes only to a HomePad this phone is linked to (Use Personal Device), only
/// after that HomePad signed a fresh nonce with the key the phone kept when it
/// linked, and only on the session that signature came in on.
@MainActor
@Observable
public final class AppleMusicSharing {
    /// The HomePads this phone shares with, by HomePad ID.
    public private(set) var sharing: [String: AppleMusicShareChoice]
    /// What each HomePad last said, by HomePad ID.
    public private(set) var states: [String: MusicLinkState] = [:]
    /// Why sharing could not turn on, by HomePad ID.
    public private(set) var errors: [String: String] = [:]
    /// Something to know that is not an error, such as Sync Library being off.
    public private(set) var notes: [String: String] = [:]
    /// HomePads a token is on its way to.
    public private(set) var busy: Set<String> = []

    @ObservationIgnored private let services: AppServices
    @ObservationIgnored private let link: PeerLink
    @ObservationIgnored private let approvals: ApprovalResponder
    @ObservationIgnored var tokens: any MusicUserTokenSource = MusicKitUserTokens()
    /// Answers on the session a message came in on. Tests keep it in memory.
    @ObservationIgnored var reply: @MainActor (PeerMessage, PeerDevice) throws -> Void
    /// Sends to a HomePad on whatever session is open, dialing if needed.
    @ObservationIgnored var transmit: @MainActor (PeerMessage, String) async throws -> Void
    @ObservationIgnored var now: () -> Date = Date.init
    /// How long to wait for the HomePad's proof and its answer. Tests shorten it.
    @ObservationIgnored var answerTimeout = AppleMusicLinkPolicy.proofLifetime
    @ObservationIgnored private var book = AppleMusicShareBook()
    /// Tokens waiting for their HomePad's proof, by request, in memory only.
    @ObservationIgnored private var heldTokens: [UUID: String] = [:]
    /// Each handoff waits for its outcome: nil once linked, else why not.
    @ObservationIgnored private var waiters: [UUID: CheckedContinuation<String?, Never>] = [:]
    @ObservationIgnored private var lastAutomaticSend: [String: Date] = [:]
    @ObservationIgnored private let log = Log.make("AppleMusicSharing")

    static let sharingKey = SettingKey<[String: AppleMusicShareChoice]>("connect.music.sharing", default: [:])
    /// Turn-offs that did not reach their HomePad yet, by HomePad ID, sent when it is next reachable.
    static let pendingUnlinksKey = SettingKey<[String: UUID]>("connect.music.pendingUnlinks", default: [:])

    init(services: AppServices, link: PeerLink, approvals: ApprovalResponder) {
        self.services = services
        self.link = link
        self.approvals = approvals
        self.sharing = services.settings[Self.sharingKey]
        self.reply = { [weak link] message, peer in
            guard let link, let session = peer.sessionID else { throw PeerLinkError.notConnected }
            try link.send(message, to: peer.id, onSession: session)
        }
        self.transmit = { [weak link] message, peerID in
            guard let link else { throw PeerLinkError.notConnected }
            try await link.send(message, to: peerID)
        }
        #if DEBUG
        if UserDefaults.standard.bool(forKey: "ConnectAppleMusicDemo") { tokens = DemoMusicUserTokens() }
        #endif
    }

    func start() {
        link.on(.musicProof) { [weak self] message, peer in
            guard let proof = try? message.content(MusicShareProof.self) else { return }
            self?.receive(proof, from: peer)
        }
        link.on(.musicState) { [weak self] message, peer in
            guard let state = try? message.content(MusicLinkState.self) else { return }
            self?.receive(state, from: peer)
        }
        link.on(.approvalState) { [weak self] message, peer in
            guard peer.kind == .homePad, let state = try? message.content(ApprovalLinkState.self) else { return }
            self?.noteLinkState(state, from: peer.id)
        }
        link.onConnect { [weak self] peer in
            guard peer.kind == .homePad else { return }
            Task { await self?.homePadConnected(peer.id) }
        }
    }

    // MARK: Turning it on and off

    public func isSharing(with homePadID: String) -> Bool { sharing[homePadID] != nil }

    /// Turns sharing on or off for one HomePad. Turning it on may ask for
    /// Apple Music access first, then sends the token.
    public func setSharing(_ isOn: Bool, with homePadID: String) async {
        errors[homePadID] = nil
        guard isOn else {
            notes[homePadID] = nil
            guard let choice = sharing[homePadID] else { return }
            sharing[homePadID] = nil
            persist()
            await sendUnlink(choice.memberID, to: homePadID)
            return
        }
        guard let member = approvals.linkedMember(on: homePadID) else {
            errors[homePadID] = "Link this iPhone to yourself on that HomePad first."
            return
        }
        guard services.settings[PhoneVisitServer.homePadKeysKey][homePadID] != nil else {
            errors[homePadID] = "\(name(of: homePadID)) hasn't shown its key yet. Try again in a moment."
            await approvals.requestState(of: homePadID)
            return
        }
        await handOff(to: homePadID, member: member, interactive: true, refresh: false)
    }

    // MARK: Handoff

    /// Gets the token from MusicKit, asks the HomePad to prove itself, and
    /// sends the token once it has. True when the HomePad kept it.
    @discardableResult
    func handOff(to homePadID: String, member: UUID, interactive: Bool, refresh: Bool) async -> Bool {
        guard !busy.contains(homePadID) else { return false }
        busy.insert(homePadID)
        defer { busy.remove(homePadID) }
        let token: String
        do {
            token = try await tokens.userToken(interactive: interactive, refresh: refresh)
        } catch {
            log.info("No Music User Token: \(String(describing: error), privacy: .public)")
            errors[homePadID] = MusicUserTokens.explanation(error)
            return false
        }
        let name = name(of: homePadID)
        if await tokens.hasCloudLibrary() == false {
            notes[homePadID] = "Sync Library is off on this iPhone, so \(name) shows your recently played and recommendations but not your library. Turn it on in Settings, Apps, Music."
        } else {
            notes[homePadID] = nil
        }
        let request = book.begin(homePadID: homePadID, memberID: member, now: now())
        heldTokens[request.requestID] = token
        let outcome = await outcome(of: request, to: homePadID)
        heldTokens[request.requestID] = nil
        book.cancel(request.requestID)
        if let outcome {
            errors[homePadID] = outcome
            return false
        }
        sharing[homePadID] = AppleMusicShareChoice(memberID: member, tokenDigest: Self.digest(token))
        persist()
        var unlinks = services.settings[Self.pendingUnlinksKey]
        if unlinks.removeValue(forKey: homePadID) != nil { services.settings[Self.pendingUnlinksKey] = unlinks }
        errors[homePadID] = nil
        log.info("Shared Apple Music with \(name, privacy: .public)")
        return true
    }

    /// Sends the share request and waits for the HomePad to keep the token or say why not.
    private func outcome(of request: MusicShareRequest, to homePadID: String) async -> String? {
        let name = name(of: homePadID)
        guard let message = try? link.message(.musicShare, request) else { return "HomePad could not ask \(name)." }
        let timeout = answerTimeout
        return await withCheckedContinuation { continuation in
            waiters[request.requestID] = continuation
            Task { [weak self] in
                do {
                    try await self?.transmit(message, homePadID)
                } catch {
                    self?.finish(request.requestID, with: "\(name) isn't reachable. Make sure this iPhone is on the home network.")
                }
            }
            Task { [weak self] in
                try? await Task.sleep(for: .seconds(timeout))
                self?.finish(request.requestID, with: "\(name) didn't answer. Try again.")
            }
        }
    }

    private func finish(_ requestID: UUID, with outcome: String?) {
        waiters.removeValue(forKey: requestID)?.resume(returning: outcome)
    }

    /// The HomePad's proof. The token goes back only if the proof checks out,
    /// and only on the session it came in on.
    func receive(_ proof: MusicShareProof, from peer: PeerDevice) {
        guard peer.kind == .homePad, peer.sessionID != nil else { return }
        let trust = AppleMusicShareBook.HomePadTrust(
            linkedMemberID: approvals.linkedMember(on: peer.id),
            homePadKey: services.settings[PhoneVisitServer.homePadKeysKey][peer.id]
        )
        switch book.verify(proof, from: peer.id, phoneID: link.identity.deviceID, trust: trust, now: now()) {
        case .success(let member):
            guard let token = heldTokens.removeValue(forKey: proof.requestID),
                  let message = try? link.message(.musicToken, MusicTokenHandoff(requestID: proof.requestID, memberID: member, userToken: token))
            else { return }
            do {
                try reply(message, peer)
            } catch {
                finish(proof.requestID, with: "Lost the connection to \(peer.name). Try again.")
            }
        case .failure(.expired):
            // Late, repeated, or from a device the request did not go to: nothing to answer.
            log.info("Ignored an Apple Music proof from \(peer.name, privacy: .public)")
        case .failure(let reason):
            heldTokens[proof.requestID] = nil
            log.info("Kept Apple Music from \(peer.name, privacy: .public): \(reason.rawValue, privacy: .public)")
            finish(proof.requestID, with: reason == .notLinked
                ? "This iPhone isn't linked to you on \(peer.name) anymore."
                : "\(peer.name) couldn't prove it is the HomePad you linked to, so your Apple Music stayed on this iPhone.")
        }
    }

    func receive(_ state: MusicLinkState, from peer: PeerDevice) {
        guard peer.kind == .homePad else { return }
        states[peer.id] = state
        if let requestID = state.requestID, waiters[requestID] != nil {
            finish(requestID, with: state.isLinked ? nil : (state.message ?? "\(peer.name) didn't keep your Apple Music. Try again."))
            return
        }
        Task { await renewIfNeeded(peer.id) }
    }

    // MARK: Keeping the HomePad's token current

    private func homePadConnected(_ homePadID: String) async {
        if let member = services.settings[Self.pendingUnlinksKey][homePadID] {
            await sendUnlink(member, to: homePadID)
        }
        await requestMusicState(of: homePadID)
    }

    /// Asks a HomePad this phone shares with what it holds now.
    private func requestMusicState(of homePadID: String) async {
        guard sharing[homePadID] != nil, let message = try? link.message(.musicStateRequest, [String: String]()) else { return }
        try? await transmit(message, homePadID)
    }

    /// Sends a new token when the HomePad needs one, lost it, or MusicKit has
    /// made a new one since. Never asks the person anything, and sends on its
    /// own at most every few hours, so a token the API keeps turning down is
    /// not sent over and over.
    func renewIfNeeded(_ homePadID: String) async {
        guard let choice = sharing[homePadID], let state = states[homePadID], state.memberID == choice.memberID,
              !busy.contains(homePadID) else { return }
        if state.needsToken || !state.isLinked {
            if let last = lastAutomaticSend[homePadID], now().timeIntervalSince(last) < AppleMusicLinkPolicy.automaticResendInterval { return }
            lastAutomaticSend[homePadID] = now()
            await handOff(to: homePadID, member: choice.memberID, interactive: false, refresh: state.needsToken)
            return
        }
        guard let token = try? await tokens.userToken(interactive: false, refresh: false),
              Self.digest(token) != choice.tokenDigest else { return }
        await handOff(to: homePadID, member: choice.memberID, interactive: false, refresh: false)
    }

    /// Stops sharing with a HomePad once this phone is no longer linked there
    /// to the same person. The HomePad forgets the token on its own then.
    /// A person who only took a new ID there, as that HomePad joined a
    /// household's setup, is the same person: sharing goes on under the new ID.
    func noteLinkState(_ state: ApprovalLinkState, from homePadID: String) {
        guard var choice = sharing[homePadID], state.linkedMemberID != choice.memberID else { return }
        if let member = state.linkedMemberID, state.formerMemberIDs?.contains(choice.memberID) == true {
            choice.memberID = member
            sharing[homePadID] = choice
            persist()
            log.info("Apple Music with \(self.name(of: homePadID), privacy: .public) goes on under the household's ID for this person")
            Task { [weak self] in await self?.requestMusicState(of: homePadID) }
            return
        }
        sharing[homePadID] = nil
        persist()
        log.info("Stopped sharing Apple Music with \(self.name(of: homePadID), privacy: .public): no longer linked there")
    }

    // MARK: Plumbing

    /// Tells the HomePad to forget the token, now or when it is next reachable.
    private func sendUnlink(_ member: UUID, to homePadID: String) async {
        var unlinks = services.settings[Self.pendingUnlinksKey]
        unlinks[homePadID] = member
        services.settings[Self.pendingUnlinksKey] = unlinks
        guard let message = try? link.message(.musicUnlink, MusicUnlink(memberID: member)) else { return }
        do {
            try await transmit(message, homePadID)
            unlinks = services.settings[Self.pendingUnlinksKey]
            unlinks[homePadID] = nil
            services.settings[Self.pendingUnlinksKey] = unlinks
        } catch {
            log.info("\(self.name(of: homePadID), privacy: .public) is not reachable. It forgets the token when it is.")
        }
    }

    private func persist() {
        services.settings[Self.sharingKey] = sharing
    }

    private func name(of homePadID: String) -> String {
        link.peer(homePadID)?.name ?? "That HomePad"
    }

    /// A short fingerprint of a token, so the phone knows when MusicKit made a
    /// new one without keeping the token itself.
    static func digest(_ token: String) -> String {
        SHA256.hash(data: Data(token.utf8)).prefix(12).map { String(format: "%02x", $0) }.joined()
    }
}

/// On a phone: sharing Apple Music with one HomePad.
public struct AppleMusicShareChoice: Codable, Equatable, Sendable {
    /// The member this phone was linked to there when it shared.
    public var memberID: UUID
    /// The fingerprint of the token sent last (`AppleMusicSharing.digest`).
    public var tokenDigest: String?
}
