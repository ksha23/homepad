import CryptoKit
import Foundation
import HomePadCore
import Testing
@testable import HomePadConnect

/// A Spotify sign-in made on a member's own iPhone and handed to a HomePad:
/// it reaches only the HomePad the phone linked to, and only that member's
/// account there.
@MainActor
@Suite struct SpotifyHandoffTests {
    // MARK: The whole way, in memory

    @Test func kylesPhoneHandsHisSpotifyToKitchenForKyleOnly() async throws {
        let loop = SpotifyLoop()
        try await loop.link()
        await loop.signIn.requestState(of: loop.pad.id)
        await loop.settle()
        let state = try #require(loop.signIn.states[loop.pad.id])
        #expect(state.isLinked)
        #expect(state.account?.isSetUp == true)
        #expect(state.account?.isSignedIn == false)

        await loop.signIn.signIn(on: loop.pad.id, homePadName: "Kitchen", authenticate: loop.spotifyPage)
        #expect(loop.signIn.errors[loop.pad.id] == nil)
        let linked = try #require(loop.accounts.linked.first)
        #expect(loop.accounts.linked.count == 1)
        #expect(linked.member == loop.kyle.id, "Kyle's own account, not Sam's or the household's")
        #expect(linked.code == "AQB")
        #expect(linked.deviceName == "Kyle's iPhone")
        // The verifier fits the challenge the phone showed Spotify, so the HomePad can exchange the code.
        #expect(SpotifyPKCE.challenge(for: linked.verifier) == loop.askedChallenge)
        #expect(loop.askedClientID == SpotifyLoop.clientID)
        #expect(loop.signIn.states[loop.pad.id]?.account?.isSignedIn == true)
        #expect(loop.signIn.states[loop.pad.id]?.account?.accountName == "kyle_s")
        // The code never crossed the link in the clear.
        let handoff = try #require(try loop.sentToPad(.spotifyHandoff).first?.content(SpotifyHandoff.self))
        #expect(!String(decoding: handoff.sealed, as: UTF8.self).contains("AQB"))
    }

    @Test func aDeviceThatIsNotTheLinkedHomePadGetsNoSignIn() async throws {
        let loop = SpotifyLoop()
        try await loop.link()
        await loop.signIn.requestState(of: loop.pad.id)
        await loop.settle()
        // The phone kept another key when it linked: whoever answers now cannot sign as that HomePad.
        var keys = loop.phoneServices.settings[PhoneVisitServer.homePadKeysKey]
        keys[loop.pad.id] = P256.Signing.PrivateKey().publicKey.rawRepresentation
        loop.phoneServices.settings[PhoneVisitServer.homePadKeysKey] = keys

        await loop.signIn.signIn(on: loop.pad.id, homePadName: "Kitchen", authenticate: loop.spotifyPage)
        #expect(loop.sentToPad(.spotifyHandoff).isEmpty, "nothing sealed is sent")
        #expect(loop.accounts.linked.isEmpty)
        #expect(loop.signIn.errors[loop.pad.id]?.contains("couldn't be verified") == true)
    }

    @Test func aPhoneNotLinkedThereCannotSignAnyoneIn() async throws {
        let loop = SpotifyLoop()
        // No link: the HomePad says so, and a hello for Kyle is refused.
        loop.phoneServices.settings[PhoneVisitServer.homePadKeysKey] = [loop.pad.id: loop.padKey.publicKey.rawRepresentation]
        await loop.signIn.requestState(of: loop.pad.id)
        await loop.settle()
        #expect(loop.signIn.states[loop.pad.id]?.isLinked == false)
        loop.toPad(try loop.phoneLink.message(.spotifyHello, SpotifyHello(memberID: loop.kyle.id, agreementKey: SpotifyHandoffSeal.newAgreementKey().publicKey.rawRepresentation)))
        await loop.settle()
        #expect(try loop.sentToPhone(.spotifyRefused).last?.content(SpotifyRefused.self).reason == .notLinked)
        #expect(loop.sentToPhone(.spotifyChallenge).isEmpty)
    }

    @Test func signingOutFromThePhoneForgetsOnlyItsMembersSpotify() async throws {
        let loop = SpotifyLoop()
        try await loop.link()
        await loop.signIn.signOut(on: loop.pad.id)
        await loop.settle()
        #expect(loop.accounts.signedOut == [loop.kyle.id])
        // Kyle's phone asking to sign Sam out is ignored.
        loop.toPad(try loop.phoneLink.message(.spotifySignOut, SpotifySignOut(memberID: loop.sam.id)))
        await loop.settle()
        #expect(loop.accounts.signedOut == [loop.kyle.id])
    }

    // MARK: The HomePad's checks

    @Test func theHomePadTakesASignInOnlyFromThePhoneLinkedToThatMember() throws {
        let padKey = HomePadKey(P256.Signing.PrivateKey())
        let phoneKey = P256.Signing.PrivateKey()
        let kyle = UUID(), sam = UUID()
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let kylesPhone = LinkedDevice(id: "phone-kyle", name: "Kyle's iPhone", kind: .iPhone, memberID: kyle,
                                      publicKey: phoneKey.publicKey.rawRepresentation, remoteVersion: RemoteProtocol.current, linkedAt: start)
        let session = SpotifyHandoffBook.Session(peerID: "phone-kyle", sessionID: UUID())
        var book = SpotifyHandoffBook()

        func hello(for member: UUID) -> (SpotifyHello, Curve25519.KeyAgreement.PrivateKey) {
            let agreement = SpotifyHandoffSeal.newAgreementKey()
            return (SpotifyHello(memberID: member, agreementKey: agreement.publicKey.rawRepresentation), agreement)
        }
        func handoff(_ hello: SpotifyHello, _ agreement: Curve25519.KeyAgreement.PrivateKey, _ challenge: SpotifyChallenge,
                     signedBy key: P256.Signing.PrivateKey) throws -> SpotifyHandoff {
            let shared = try SpotifyHandoffSeal.key(privateKey: agreement, peerKey: challenge.agreementKey, hello: hello, homePadNonce: challenge.nonce)
            let sealed = try SpotifyHandoffSeal.seal(SpotifySignInCode(code: "AQB", verifier: "v"), with: shared, requestID: hello.requestID)
            let bytes = SpotifyHandoff.signedBytes(hello: hello, challenge: challenge, sealed: sealed, homePadID: "pad", phoneID: "phone-kyle")
            return SpotifyHandoff(requestID: hello.requestID, sealed: sealed, signature: try key.signature(for: bytes).rawRepresentation)
        }

        // Kyle's phone cannot hand a sign-in to Sam, and an unlinked device to anyone.
        #expect(book.hello(hello(for: sam).0, on: session, linked: kylesPhone, homePadID: "pad", sign: padKey.sign, now: start) == .failure(.notLinked))
        #expect(book.hello(hello(for: kyle).0, on: session, linked: nil, homePadID: "pad", sign: padKey.sign, now: start) == .failure(.notLinked))

        let (good, agreement) = hello(for: kyle)
        let challenge = try book.hello(good, on: session, linked: kylesPhone, homePadID: "pad", sign: padKey.sign, now: start).get()
        // The phone checks the HomePad's signature with the key it kept.
        let challengeBytes = SpotifyChallenge.signedBytes(hello: good, nonce: challenge.nonce, agreementKey: challenge.agreementKey,
                                                          homePadID: "pad", phoneID: "phone-kyle")
        #expect(HomePadKey.isValid(challenge.signature, of: challengeBytes, by: padKey.publicKey))

        // Signed by another household device's key: dropped, and the request stays open.
        let forged = try handoff(good, agreement, challenge, signedBy: P256.Signing.PrivateKey())
        #expect(refusal(book.handoff(forged, on: session, linked: kylesPhone, homePadID: "pad", now: start)) == .notVerified)
        // On another session with the phone's ID: dropped.
        let real = try handoff(good, agreement, challenge, signedBy: phoneKey)
        let other = SpotifyHandoffBook.Session(peerID: "phone-kyle", sessionID: UUID())
        #expect(refusal(book.handoff(real, on: other, linked: kylesPhone, homePadID: "pad", now: start)) == .notVerified)
        // Kyle's phone, on its session, in time: Kyle's code.
        let taken = try book.handoff(real, on: session, linked: kylesPhone, homePadID: "pad", now: start.addingTimeInterval(5)).get()
        #expect(taken.member == kyle)
        #expect(taken.signIn == SpotifySignInCode(code: "AQB", verifier: "v"))
        // Used once.
        #expect(refusal(book.handoff(real, on: session, linked: kylesPhone, homePadID: "pad", now: start)) == .expired)

        // Too late.
        let (late, lateAgreement) = hello(for: kyle)
        let lateChallenge = try book.hello(late, on: session, linked: kylesPhone, homePadID: "pad", sign: padKey.sign, now: start).get()
        let lateHandoff = try handoff(late, lateAgreement, lateChallenge, signedBy: phoneKey)
        #expect(refusal(book.handoff(lateHandoff, on: session, linked: kylesPhone, homePadID: "pad",
                                     now: start.addingTimeInterval(SpotifyHandoffPolicy.lifetime + 1))) == .expired)
    }

    /// A device in the middle that swaps in its own agreement key cannot read the sign-in.
    @Test func onlyTheHomePadsAgreementKeyOpensTheSignIn() throws {
        let phone = SpotifyHandoffSeal.newAgreementKey(), pad = SpotifyHandoffSeal.newAgreementKey()
        let middle = SpotifyHandoffSeal.newAgreementKey()
        let hello = SpotifyHello(memberID: UUID(), agreementKey: phone.publicKey.rawRepresentation)
        let nonce = ApprovalRequest.randomNonce()
        let phoneSide = try SpotifyHandoffSeal.key(privateKey: phone, peerKey: pad.publicKey.rawRepresentation, hello: hello, homePadNonce: nonce)
        let sealed = try SpotifyHandoffSeal.seal(SpotifySignInCode(code: "AQB", verifier: "v"), with: phoneSide, requestID: hello.requestID)
        let padSide = try SpotifyHandoffSeal.key(privateKey: pad, peerKey: phone.publicKey.rawRepresentation, hello: hello, homePadNonce: nonce)
        #expect(try SpotifyHandoffSeal.open(sealed, with: padSide, requestID: hello.requestID).code == "AQB")
        let middleSide = try SpotifyHandoffSeal.key(privateKey: middle, peerKey: phone.publicKey.rawRepresentation, hello: hello, homePadNonce: nonce)
        #expect(throws: (any Error).self) { try SpotifyHandoffSeal.open(sealed, with: middleSide, requestID: hello.requestID) }
        #expect(throws: (any Error).self) { try SpotifyHandoffSeal.open(sealed, with: padSide, requestID: UUID()) }
    }

    private func refusal<T>(_ result: Result<T, SpotifyRefusal>) -> SpotifyRefusal? {
        if case .failure(let reason) = result { return reason }
        return nil
    }
}

/// A HomePad and Kyle's iPhone joined in memory for the Spotify handoff, with
/// made-up Spotify accounts on the HomePad. Every message crosses
/// `MessageCodec` and carries the session it came on.
@MainActor
final class SpotifyLoop {
    static let clientID = "0123456789abcdef0123456789abcdef"

    let padServices: AppServices
    let padLink: PeerLink
    let approver: PersonalDeviceApprover
    let receiver: SpotifyHandoffReceiver
    let accounts = FakeSpotifyAccounts()
    let phoneServices: AppServices
    let phoneLink: PeerLink
    let approvals: ApprovalResponder
    let photoSharing: PhoneLibraryServer
    let visitServer: PhoneVisitServer
    let signIn: PhoneSpotifySignIn
    let pad = PeerDevice(id: "pad-kitchen", name: "Kitchen", kind: .homePad, isConnected: true)
    let phoneDevice = PeerDevice(id: "phone-kyle", name: "iPhone", kind: .iPhone, isConnected: true)
    let kyle = HouseholdMember(name: "Kyle", avatar: "🦊", isAdmin: true)
    let sam = HouseholdMember(name: "Sam", avatar: "🐼")
    let padKey = P256.Signing.PrivateKey()
    let phoneKey = P256.Signing.PrivateKey()
    var session = UUID()
    /// What the phone showed Spotify.
    private(set) var askedChallenge: String?
    private(set) var askedClientID: String?
    private(set) var toPadLog: [PeerMessage] = []
    private(set) var toPhoneLog: [PeerMessage] = []

    init() {
        padServices = AppServices(settings: RemoteLoop.freshSettings())
        padServices.household.add(kyle)
        padServices.household.add(sam)
        padLink = PeerLink(services: padServices)
        padLink.identity = LocalIdentity(deviceID: pad.id, name: pad.name, kind: .homePad)
        approver = PersonalDeviceApprover(services: padServices, link: padLink)
        approver.homePadKey = HomePadKey(padKey)
        receiver = SpotifyHandoffReceiver(services: padServices, link: padLink, approver: approver)
        phoneServices = AppServices(settings: RemoteLoop.freshSettings())
        phoneLink = PeerLink(services: phoneServices)
        phoneLink.identity = LocalIdentity(deviceID: phoneDevice.id, name: phoneDevice.name, kind: .iPhone)
        approvals = ApprovalResponder(services: phoneServices, link: phoneLink)
        visitServer = PhoneVisitServer(services: phoneServices, link: phoneLink, approvals: approvals)
        photoSharing = PhoneLibraryServer(visit: visitServer)
        visitServer.add(photoSharing)
        signIn = PhoneSpotifySignIn(services: phoneServices, link: phoneLink, approvals: approvals)

        let accounts = accounts
        receiver.accounts = { accounts }
        receiver.reply = { [unowned self] message, peer in toPhone(message, session: peer.sessionID) }
        approver.verifyOwner = { _ in true }
        approver.transmit = { [unowned self] message, _ in toPhone(message) }
        approvals.publicKey = { [phoneKey] in phoneKey.publicKey.rawRepresentation }
        approvals.notifications = SilentApprovalNotifications()
        approvals.transmit = { [unowned self] message, _ in toPad(message) }
        photoSharing.reader = FakePhoneLibrary()
        visitServer.window = FakeWindow()
        visitServer.makeWakeListener = { FakeWakeListener() }
        signIn.transmit = { [unowned self] message, _ in toPad(message) }
        signIn.transmitOnSession = { [unowned self] message, _, onSession in
            guard onSession == session else { throw PeerLinkError.notConnected }
            toPad(message, session: onSession)
        }
        signIn.sign = { [phoneKey] data, _ in try phoneKey.signature(for: data).rawRepresentation }
        signIn.replyTimeout = 0.5

        approver.start()
        receiver.start()
        approvals.start()
        photoSharing.start()
        visitServer.start()
        signIn.start()
    }

    /// Spotify's page: Kyle signs in and Spotify sends back a code.
    var spotifyPage: @MainActor (URL, String) async throws -> URL {
        { [unowned self] url, scheme in
            let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
            askedChallenge = items.first { $0.name == "code_challenge" }?.value
            askedClientID = items.first { $0.name == "client_id" }?.value
            let state = items.first { $0.name == "state" }?.value ?? ""
            return URL(string: "\(scheme)://callback?code=AQB&state=\(state)")!
        }
    }

    func toPad(_ message: PeerMessage, session: UUID? = nil) {
        let received = RemoteLoop.overTheWire(message)
        toPadLog.append(received)
        var device = phoneDevice
        device.sessionID = session ?? self.session
        padLink.dispatch(received, from: device)
    }

    func toPhone(_ message: PeerMessage, session: UUID? = nil) {
        let received = RemoteLoop.overTheWire(message)
        toPhoneLog.append(received)
        var device = pad
        device.sessionID = session ?? self.session
        phoneLink.dispatch(received, from: device)
    }

    func sentToPad(_ type: PeerMessageType) -> [PeerMessage] { toPadLog.filter { $0.type == type } }
    func sentToPhone(_ type: PeerMessageType) -> [PeerMessage] { toPhoneLog.filter { $0.type == type } }

    func settle() async {
        for _ in 0..<60 { await Task.yield() }
    }

    /// Links the phone to Kyle, allowed at the HomePad. The phone keeps the HomePad's key then.
    func link() async throws {
        await approvals.requestState(of: pad.id)
        await settle()
        let choice = try #require(approvals.states[pad.id]?.members.first { $0.id == kyle.id })
        await approvals.linkMember(choice, on: pad.id)
        await settle()
        await approver.allow(try #require(approver.pendingLinks.first))
        await settle()
        #expect(phoneServices.settings[PhoneVisitServer.homePadKeysKey][pad.id] == padKey.publicKey.rawRepresentation)
    }
}

/// Members' Spotify on the HomePad, in memory: set up, nobody signed in yet.
@MainActor
final class FakeSpotifyAccounts: SpotifyMemberAccounts {
    struct Linked: Equatable {
        var member: UUID
        var code: String
        var verifier: String
        var deviceName: String
    }

    private(set) var linked: [Linked] = []
    private(set) var signedOut: [UUID] = []

    func spotifyAccount(for member: UUID) -> SpotifyMemberAccount {
        let isSignedIn = linked.contains { $0.member == member } && !signedOut.contains(member)
        return SpotifyMemberAccount(isSetUp: true, clientID: SpotifyLoop.clientID, accountName: isSignedIn ? "kyle_s" : nil,
                                    isSignedIn: isSignedIn)
    }

    func linkSpotify(code: String, verifier: String, for member: UUID, from deviceName: String) async throws -> SpotifyMemberAccount {
        linked.append(Linked(member: member, code: code, verifier: verifier, deviceName: deviceName))
        return spotifyAccount(for: member)
    }

    func signOutSpotify(for member: UUID) {
        signedOut.append(member)
    }
}
