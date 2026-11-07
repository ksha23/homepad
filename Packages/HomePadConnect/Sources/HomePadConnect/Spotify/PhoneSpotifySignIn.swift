import AuthenticationServices
import CryptoKit
import Foundation
import HomePadCore
import Observation

/// On an iPhone: signs its owner in to Spotify on the phone and hands the
/// sign-in to a HomePad they are linked to, so nobody types a password on
/// the wall.
///
/// 1. The HomePad says where the member's Spotify stands, with the household's
///    client ID (`spotify.state`).
/// 2. Spotify's sign-in runs on the phone, for that client ID.
/// 3. The phone hands Spotify's one-time code over only after the HomePad
///    signs a fresh challenge with the key the phone kept when it linked, the
///    same key that guards its photos. The code is sealed to a one-time key
///    only that HomePad holds (`SpotifyHandoffSeal`), and signed with this
///    phone's approval key after Face ID, so the HomePad knows it comes from
///    the member's own phone.
/// 4. The HomePad exchanges the code for tokens and keeps them for that
///    member. The phone keeps nothing.
@MainActor
@Observable
public final class PhoneSpotifySignIn {
    /// What each HomePad said about this phone's member, by HomePad ID.
    public private(set) var states: [String: SpotifyStateReply] = [:]
    /// HomePads with a sign-in or sign-out under way.
    public private(set) var busy: Set<String> = []
    /// Why the last sign-in did not work, by HomePad ID.
    public private(set) var errors: [String: String] = [:]

    @ObservationIgnored private let services: AppServices
    @ObservationIgnored private let link: PeerLink
    @ObservationIgnored private let approvals: ApprovalResponder
    /// Sends to a HomePad on whatever session is open.
    @ObservationIgnored var transmit: @MainActor (PeerMessage, String) async throws -> Void
    /// Sends on one session only: the one the HomePad's challenge came on.
    @ObservationIgnored var transmitOnSession: @MainActor (PeerMessage, String, UUID) throws -> Void
    /// Verifies the person and signs with this phone's approval key.
    @ObservationIgnored var sign: @MainActor (Data, String) async throws -> Data = DeviceApprovalKey.signApproval
    /// The HomePad's key this phone kept when it linked, nil before.
    @ObservationIgnored var homePadKey: @MainActor (String) -> Data?
    @ObservationIgnored var replyTimeout = SpotifyHandoffPolicy.replyTimeout
    /// The HomePad each open request was sent to, by request ID.
    @ObservationIgnored private var expected: [UUID: String] = [:]
    /// Answers that came before their request began to wait.
    @ObservationIgnored private var early: [UUID: Answer] = [:]
    @ObservationIgnored private var waiters: [UUID: CheckedContinuation<Answer?, Never>] = [:]
    @ObservationIgnored private let log = Log.make("SpotifyHandoff")

    /// The HomePad's answer to one request, with the session it came on.
    private struct Answer {
        let message: PeerMessage
        let sessionID: UUID?
    }

    init(services: AppServices, link: PeerLink, approvals: ApprovalResponder) {
        self.services = services
        self.link = link
        self.approvals = approvals
        self.transmit = { [weak link] message, peerID in
            guard let link else { throw PeerLinkError.notConnected }
            try await link.send(message, to: peerID)
        }
        self.transmitOnSession = { [weak link] message, peerID, sessionID in
            guard let link else { throw PeerLinkError.notConnected }
            try link.send(message, to: peerID, onSession: sessionID)
        }
        self.homePadKey = { [weak services] homePadID in
            services?.settings[PhoneVisitServer.homePadKeysKey][homePadID]
        }
        #if DEBUG
        if UserDefaults.standard.bool(forKey: "ConnectApprovalSkipVerify") {
            sign = { data, _ in try DeviceApprovalKey.signWithoutVerifying(data) }
        }
        #endif
    }

    func start() {
        link.on(.spotifyState) { [weak self] message, peer in
            guard peer.kind == .homePad, let state = try? message.content(SpotifyStateReply.self) else { return }
            self?.states[peer.id] = state
        }
        for type in [PeerMessageType.spotifyChallenge, .spotifyRefused, .spotifyResult] {
            link.on(type) { [weak self] message, peer in
                self?.answer(message, from: peer)
            }
        }
        link.onConnect { [weak self] peer in
            guard peer.kind == .homePad else { return }
            Task { await self?.requestState(of: peer.id) }
        }
    }

    // MARK: State

    /// Asks a HomePad where this phone's member's Spotify stands there.
    public func requestState(of homePadID: String) async {
        guard let message = try? link.message(.spotifyStateRequest, [String: String]()) else { return }
        try? await transmit(message, homePadID)
    }

    // MARK: Signing in

    /// Signs in to Spotify on this phone and hands the sign-in to a HomePad.
    /// `authenticate` shows Spotify's page and returns the callback URL.
    public func signIn(on homePadID: String, homePadName: String,
                       authenticate: @MainActor (URL, String) async throws -> URL) async {
        guard !busy.contains(homePadID) else { return }
        busy.insert(homePadID)
        defer { busy.remove(homePadID) }
        errors[homePadID] = nil
        do {
            let account = try await handOver(on: homePadID, homePadName: homePadName, authenticate: authenticate)
            states[homePadID] = SpotifyStateReply(isLinked: true, account: account)
        } catch DeviceApprovalKey.Failure.cancelled {
            // Face ID was cancelled. Nothing was sent.
        } catch let error as ASWebAuthenticationSessionError where error.code == .canceledLogin {
            // The person closed Spotify's page.
        } catch {
            log.info("Spotify sign-in for \(homePadName, privacy: .public) did not finish: \(error.localizedDescription, privacy: .public)")
            errors[homePadID] = error.localizedDescription
        }
    }

    private func handOver(on homePadID: String, homePadName: String,
                          authenticate: @MainActor (URL, String) async throws -> URL) async throws -> SpotifyMemberAccount {
        guard let member = approvals.linkedMember(on: homePadID) else { throw SignInFailure.notLinked }
        guard let account = states[homePadID]?.account, account.isSetUp, let clientID = account.clientID else {
            throw SignInFailure.notSetUp(homePadName)
        }
        guard let padKey = homePadKey(homePadID) else { throw SignInFailure.noHomePadKey(homePadName) }

        // Spotify's own page, on this phone. It may remember a sign-in from
        // Safari, and asks which account so a shared browser cannot pick for you.
        let verifier = SpotifyPKCE.makeVerifier()
        let state = UUID().uuidString
        let callback = try await authenticate(
            SpotifyPKCE.authorizationURL(clientID: clientID, verifier: verifier, state: state, showDialog: true),
            SpotifyPKCE.callbackScheme)
        let code = try SpotifyPKCE.code(from: callback, state: state)

        // The HomePad proves it is the one this phone linked to.
        let agreement = SpotifyHandoffSeal.newAgreementKey()
        let hello = SpotifyHello(memberID: member, agreementKey: agreement.publicKey.rawRepresentation)
        let reply = try await ask(.spotifyHello, hello, requestID: hello.requestID, of: homePadID)
        if let refused = try? reply.message.content(SpotifyRefused.self), reply.message.type == .spotifyRefused {
            throw SignInFailure.refused(refused.reason, homePadName)
        }
        guard reply.message.type == .spotifyChallenge, let sessionID = reply.sessionID,
              let challenge = try? reply.message.content(SpotifyChallenge.self) else { throw SignInFailure.noAnswer(homePadName) }
        let challengeBytes = SpotifyChallenge.signedBytes(hello: hello, nonce: challenge.nonce, agreementKey: challenge.agreementKey,
                                                          homePadID: homePadID, phoneID: link.identity.deviceID)
        guard challenge.nonce.count == 32, HomePadKey.isValid(challenge.signature, of: challengeBytes, by: padKey) else {
            throw SignInFailure.refused(.notVerified, homePadName)
        }

        // Sealed to that HomePad, and signed after Face ID.
        let key = try SpotifyHandoffSeal.key(privateKey: agreement, peerKey: challenge.agreementKey,
                                             hello: hello, homePadNonce: challenge.nonce)
        let sealed = try SpotifyHandoffSeal.seal(SpotifySignInCode(code: code, verifier: verifier), with: key, requestID: hello.requestID)
        let bytes = SpotifyHandoff.signedBytes(hello: hello, challenge: challenge, sealed: sealed,
                                               homePadID: homePadID, phoneID: link.identity.deviceID)
        let signature = try await sign(bytes, "Use your Spotify on \(homePadName)")
        let handoff = SpotifyHandoff(requestID: hello.requestID, sealed: sealed, signature: signature)
        let result = try await ask(.spotifyHandoff, handoff, requestID: hello.requestID, of: homePadID, onSession: sessionID)
        if result.message.type == .spotifyRefused, let refused = try? result.message.content(SpotifyRefused.self) {
            throw SignInFailure.refused(refused.reason, homePadName)
        }
        guard let body = try? result.message.content(SpotifyResult.self) else { throw SignInFailure.noAnswer(homePadName) }
        if let account = body.account { states[homePadID] = SpotifyStateReply(isLinked: true, account: account) }
        if let error = body.error { throw SignInFailure.spotify(error) }
        return body.account ?? account
    }

    /// Signs this phone's member out of Spotify on a HomePad.
    public func signOut(on homePadID: String) async {
        guard let member = approvals.linkedMember(on: homePadID),
              let message = try? link.message(.spotifySignOut, SpotifySignOut(memberID: member)) else { return }
        busy.insert(homePadID)
        defer { busy.remove(homePadID) }
        do {
            try await transmit(message, homePadID)
            errors[homePadID] = nil
        } catch {
            errors[homePadID] = error.localizedDescription
        }
    }

    // MARK: Waiting for answers

    /// Sends one message and waits for the HomePad's answer to it.
    private func ask(_ type: PeerMessageType, _ body: some Encodable, requestID: UUID, of homePadID: String,
                     onSession sessionID: UUID? = nil) async throws -> Answer {
        let message = try link.message(type, body)
        expected[requestID] = homePadID
        defer {
            expected[requestID] = nil
            early[requestID] = nil
        }
        if let sessionID {
            // The HomePad's challenge came on this session. Another one may be someone else's.
            try transmitOnSession(message, homePadID, sessionID)
        } else {
            try await transmit(message, homePadID)
        }
        if let answer = early[requestID] { return answer }
        let timeout = replyTimeout
        let answer = await withCheckedContinuation { continuation in
            waiters[requestID] = continuation
            Task { [weak self] in
                try? await Task.sleep(for: .seconds(timeout))
                self?.finish(requestID, with: nil)
            }
        }
        guard let answer else { throw SignInFailure.noAnswer(link.peer(homePadID)?.name ?? "The HomePad") }
        return answer
    }

    /// An answer counts only from the HomePad that was asked.
    private func answer(_ message: PeerMessage, from peer: PeerDevice) {
        guard let requestID = try? message.content(AnswerHeader.self).requestID, expected[requestID] == peer.id else { return }
        let answer = Answer(message: message, sessionID: peer.sessionID)
        if waiters[requestID] == nil {
            early[requestID] = answer
        } else {
            finish(requestID, with: answer)
        }
    }

    /// What every answer has: the request it answers.
    private struct AnswerHeader: Decodable {
        let requestID: UUID
    }

    private func finish(_ requestID: UUID, with answer: Answer?) {
        waiters.removeValue(forKey: requestID)?.resume(returning: answer)
    }
}

/// Why a Spotify sign-in from the phone did not reach the HomePad, in words.
enum SignInFailure: LocalizedError {
    case notLinked
    case notSetUp(String)
    case noHomePadKey(String)
    case refused(SpotifyRefusal, String)
    case noAnswer(String)
    case spotify(String)

    var errorDescription: String? {
        switch self {
        case .notLinked:
            "Link this iPhone to yourself on that HomePad first, under Unlock With This iPhone."
        case .notSetUp(let name):
            "Spotify isn't set up on \(name) yet. Turn it on in Settings there, under Audio and AirPlay, Spotify."
        case .noHomePadKey(let name):
            "This iPhone doesn't know \(name)'s key yet. Stop unlocking with it below, then link it again."
        case .refused(.notLinked, let name):
            "\(name) doesn't have this iPhone linked to you. Link it again under Unlock With This iPhone."
        case .refused(.notSetUp, let name):
            "Spotify isn't set up on \(name) yet. Turn it on in Settings there, under Audio and AirPlay, Spotify."
        case .refused(.notVerified, let name):
            "\(name) couldn't be verified, so your Spotify sign-in wasn't sent. Try again, or link this iPhone again."
        case .refused(.expired, _):
            "That took too long. Try again."
        case .noAnswer(let name):
            "\(name) didn't answer. Open HomePad there, or check this iPhone is on your home Wi-Fi."
        case .spotify(let reason):
            reason
        }
    }
}
