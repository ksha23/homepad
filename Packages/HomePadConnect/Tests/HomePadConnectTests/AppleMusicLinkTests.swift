import CryptoKit
import Foundation
import HomePadCore
import Testing
@testable import HomePadConnect

/// A HomePad and Kyle's iPhone joined in memory for Apple Music, after the
/// iPhone linked to Kyle. Every message crosses `MessageCodec` and carries
/// the session it came on, like a sealed session.
@MainActor
final class MusicLoop {
    let padServices: AppServices
    let padLink: PeerLink
    let approver: PersonalDeviceApprover
    let links: AppleMusicLinks
    let phoneServices: AppServices
    let phoneLink: PeerLink
    let approvals: ApprovalResponder
    let photos: PhoneLibraryServer
    let visitServer: PhoneVisitServer
    let sharing: AppleMusicSharing
    let tokens = FakeMusicTokens()
    let secrets = MemorySecrets()
    let pad = PeerDevice(id: "pad-kitchen", name: "Kitchen", kind: .homePad, isConnected: true)
    let phoneDevice = PeerDevice(id: "phone-kyle", name: "iPhone", kind: .iPhone, isConnected: true)
    let kyle = HouseholdMember(name: "Kyle", avatar: "🦊", isAdmin: true)
    let sam = HouseholdMember(name: "Sam", avatar: "🐼")
    let padKey = P256.Signing.PrivateKey()
    var session: UUID? = UUID()
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
        links = AppleMusicLinks(services: padServices, link: padLink, approver: approver)
        links.secrets = secrets
        phoneServices = AppServices(settings: RemoteLoop.freshSettings())
        phoneLink = PeerLink(services: phoneServices)
        phoneLink.identity = LocalIdentity(deviceID: phoneDevice.id, name: phoneDevice.name, kind: .iPhone)
        approvals = ApprovalResponder(services: phoneServices, link: phoneLink)
        visitServer = PhoneVisitServer(services: phoneServices, link: phoneLink, approvals: approvals)
        photos = PhoneLibraryServer(visit: visitServer)
        visitServer.add(photos)
        sharing = AppleMusicSharing(services: phoneServices, link: phoneLink, approvals: approvals)

        approver.verifyOwner = { _ in true }
        approver.transmit = { [unowned self] message, _ in toPhone(message) }
        links.reply = { [unowned self] message, peer in toPhone(message, session: peer.sessionID) }
        links.transmit = { [unowned self] message, _ in toPhone(message) }
        approvals.publicKey = { P256.Signing.PrivateKey().publicKey.rawRepresentation }
        approvals.notifications = SilentApprovalNotifications()
        approvals.transmit = { [unowned self] message, _ in toPad(message) }
        photos.reader = FakePhoneLibrary()
        visitServer.window = FakeWindow()
        visitServer.makeWakeListener = { FakeWakeListener() }
        sharing.tokens = tokens
        sharing.answerTimeout = 0.5
        sharing.reply = { [unowned self] message, peer in toPad(message, session: peer.sessionID) }
        sharing.transmit = { [unowned self] message, _ in
            guard session != nil else { throw PeerLinkError.notConnected }
            toPad(message)
        }

        approver.start()
        links.start()
        approvals.start()
        photos.start()
        visitServer.start()
        sharing.start()
    }

    func toPad(_ message: PeerMessage, session: UUID? = nil, from device: PeerDevice? = nil) {
        let received = RemoteLoop.overTheWire(message)
        toPadLog.append(received)
        var device = device ?? phoneDevice
        device.sessionID = session ?? self.session
        padLink.dispatch(received, from: device)
    }

    func toPhone(_ message: PeerMessage, session: UUID? = nil, from device: PeerDevice? = nil) {
        let received = RemoteLoop.overTheWire(message)
        toPhoneLog.append(received)
        var device = device ?? pad
        device.sessionID = session ?? self.session
        phoneLink.dispatch(received, from: device)
    }

    func sentToPad(_ type: PeerMessageType) -> [PeerMessage] { toPadLog.filter { $0.type == type } }
    func sentToPhone(_ type: PeerMessageType) -> [PeerMessage] { toPhoneLog.filter { $0.type == type } }

    func settle() async {
        for _ in 0..<60 { await Task.yield() }
    }

    /// Links the phone to Kyle, with Kyle at the HomePad. The phone keeps the HomePad's key.
    func linkToKyle() async throws {
        await approvals.requestState(of: pad.id)
        await settle()
        let choice = try #require(approvals.states[pad.id]?.members.first { $0.id == kyle.id })
        await approvals.linkMember(choice, on: pad.id)
        await settle()
        await approver.allow(try #require(approver.pendingLinks.first))
        await settle()
    }
}

/// Tokens as MusicKit would give them, counting each ask.
@MainActor
final class FakeMusicTokens: MusicUserTokenSource {
    var token = "kyle-token-1"
    private(set) var refreshes = 0

    func userToken(interactive: Bool, refresh: Bool) async throws -> String {
        if refresh {
            refreshes += 1
            token = "kyle-token-\(refreshes + 1)"
        }
        return token
    }

    func hasCloudLibrary() async -> Bool? { true }
}

@MainActor
@Suite("Apple Music handoff")
struct AppleMusicHandoffTests {
    @Test("The token goes to the linked HomePad, filed under the phone's own member")
    func handsTheTokenToTheRightMember() async throws {
        let loop = MusicLoop()
        try await loop.linkToKyle()
        await loop.sharing.setSharing(true, with: loop.pad.id)
        await loop.settle()

        #expect(loop.links.userToken(for: loop.kyle.id) == "kyle-token-1")
        #expect(loop.links.userToken(for: loop.sam.id) == nil)
        #expect(loop.links.links[loop.kyle.id]?.deviceID == loop.phoneDevice.id)
        #expect(loop.sharing.isSharing(with: loop.pad.id))
        #expect(loop.sharing.states[loop.pad.id]?.isLinked == true)
        // The token went once, after the HomePad's proof, and never in the HomePad's own messages.
        #expect(loop.sentToPad(.musicToken).count == 1)
        #expect(!loop.toPhoneLog.contains { "\($0.body)".contains("kyle-token") })
    }

    @Test("A HomePad that cannot sign with the key the phone kept gets no token")
    func keepsTheTokenFromAHomePadThatCannotProveItself() async throws {
        let loop = MusicLoop()
        try await loop.linkToKyle()
        // The phone kept another key, as when a household device answered as the HomePad at link time.
        var keys = loop.phoneServices.settings[PhoneVisitServer.homePadKeysKey]
        keys[loop.pad.id] = P256.Signing.PrivateKey().publicKey.rawRepresentation
        loop.phoneServices.settings[PhoneVisitServer.homePadKeysKey] = keys

        await loop.sharing.setSharing(true, with: loop.pad.id)
        await loop.settle()

        #expect(loop.sentToPad(.musicShare).count == 1)
        #expect(loop.sentToPad(.musicToken).isEmpty)
        #expect(loop.links.userToken(for: loop.kyle.id) == nil)
        #expect(!loop.sharing.isSharing(with: loop.pad.id))
        #expect(loop.sharing.errors[loop.pad.id]?.contains("couldn't prove") == true)
    }

    @Test("A proof from another device, even with the right request, sends nothing")
    func ignoresAProofFromAnotherDevice() async throws {
        let loop = MusicLoop()
        try await loop.linkToKyle()
        let impostor = PeerDevice(id: "pad-impostor", name: "Kitchen", kind: .homePad, isConnected: true)
        // Every proof the HomePad sends goes to the phone as if from the impostor instead.
        loop.links.reply = { [unowned loop] message, peer in loop.toPhone(message, session: peer.sessionID, from: impostor) }

        await loop.sharing.setSharing(true, with: loop.pad.id)
        await loop.settle()

        #expect(loop.sentToPad(.musicToken).isEmpty)
        #expect(loop.links.userToken(for: loop.kyle.id) == nil)
    }

    @Test("A phone gets no proof for someone it is not linked to, and none before it links")
    func refusesSharesForTheWrongMember() async throws {
        let loop = MusicLoop()
        let early = MusicShareRequest(memberID: loop.kyle.id)
        loop.toPad(try loop.phoneLink.message(.musicShare, early))
        try await loop.linkToKyle()
        let forSam = MusicShareRequest(memberID: loop.sam.id)
        loop.toPad(try loop.phoneLink.message(.musicShare, forSam))
        await loop.settle()

        #expect(loop.sentToPhone(.musicProof).isEmpty)
        let answers = try loop.sentToPhone(.musicState).map { try $0.content(MusicLinkState.self) }
        #expect(answers.contains { $0.requestID == early.requestID && $0.message != nil })
        #expect(answers.contains { $0.requestID == forSam.requestID && $0.message != nil })
    }

    @Test("Turning it off on the phone deletes the token on the HomePad")
    func turningItOffForgetsTheToken() async throws {
        let loop = MusicLoop()
        try await loop.linkToKyle()
        await loop.sharing.setSharing(true, with: loop.pad.id)
        await loop.settle()
        await loop.sharing.setSharing(false, with: loop.pad.id)
        await loop.settle()

        #expect(loop.links.userToken(for: loop.kyle.id) == nil)
        #expect(loop.links.links.isEmpty)
        #expect(loop.secrets.string(for: "token.\(loop.kyle.id.uuidString)") == nil)
        #expect(!loop.sharing.isSharing(with: loop.pad.id))
    }

    @Test("Unlinking the phone, or removing the person, deletes the token")
    func unlinkingOrLeavingForgetsTheToken() async throws {
        let loop = MusicLoop()
        try await loop.linkToKyle()
        await loop.sharing.setSharing(true, with: loop.pad.id)
        await loop.settle()
        loop.approver.remove(loop.phoneDevice.id)
        await loop.settle()
        #expect(loop.links.userToken(for: loop.kyle.id) == nil)
        #expect(!loop.sharing.isSharing(with: loop.pad.id))

        let again = MusicLoop()
        try await again.linkToKyle()
        await again.sharing.setSharing(true, with: again.pad.id)
        await again.settle()
        again.padServices.household.remove(again.kyle.id)
        await again.settle()
        #expect(again.links.userToken(for: again.kyle.id) == nil)
        #expect(again.secrets.string(for: "token.\(again.kyle.id.uuidString)") == nil)
    }

    @Test("A token Apple turned down is forgotten, and the phone sends a fresh one")
    func aRejectedTokenIsRenewed() async throws {
        let loop = MusicLoop()
        try await loop.linkToKyle()
        await loop.sharing.setSharing(true, with: loop.pad.id)
        await loop.settle()

        loop.links.tokenRejected(for: loop.kyle.id)
        #expect(loop.links.userToken(for: loop.kyle.id) == nil)
        #expect(loop.links.links[loop.kyle.id]?.needsNewToken == true)
        await loop.settle()
        await loop.settle()

        #expect(loop.tokens.refreshes == 1)
        #expect(loop.links.userToken(for: loop.kyle.id) == "kyle-token-2")
        #expect(loop.links.links[loop.kyle.id]?.needsNewToken == false)
    }

    @Test("Joining a household's setup keeps a person's Apple Music under their new ID")
    func joiningKeepsAppleMusic() async throws {
        let loop = MusicLoop()
        try await loop.linkToKyle()
        await loop.sharing.setSharing(true, with: loop.pad.id)
        await loop.settle()
        // As ConnectRuntime wires it.
        loop.padServices.household.onMemberIDChange { [links = loop.links, approver = loop.approver] old, new in
            links.moveMember(from: old, to: new)
            approver.moveLinks(from: old, to: new)
        }
        let old = loop.kyle.id
        let new = UUID()

        loop.padServices.household.changeMemberID(from: old, to: new)
        await loop.settle()
        await loop.settle()

        #expect(loop.links.userToken(for: new) == "kyle-token-1")
        #expect(loop.links.links[old] == nil)
        #expect(loop.secrets.string(for: "token.\(old.uuidString)") == nil)
        #expect(loop.sharing.sharing[loop.pad.id]?.memberID == new)
        #expect(loop.links.state(for: loop.phoneDevice.id).isLinked)

        // A token Apple turns down later is renewed under the new ID.
        loop.links.tokenRejected(for: new)
        await loop.settle()
        await loop.settle()
        #expect(loop.links.userToken(for: new) == "kyle-token-2")
    }

    @Test("A phone linked to someone else stops sharing, unless they are the same person under a new ID")
    func onlyTheSamePersonCarriesOver() async throws {
        let loop = MusicLoop()
        try await loop.linkToKyle()
        await loop.sharing.setSharing(true, with: loop.pad.id)
        await loop.settle()
        let new = UUID()

        loop.sharing.noteLinkState(ApprovalLinkState(linkedMemberID: new, formerMemberIDs: [loop.kyle.id]), from: loop.pad.id)
        #expect(loop.sharing.sharing[loop.pad.id]?.memberID == new)

        loop.sharing.noteLinkState(ApprovalLinkState(linkedMemberID: loop.sam.id, formerMemberIDs: [UUID()]), from: loop.pad.id)
        #expect(!loop.sharing.isSharing(with: loop.pad.id))
    }

    @Test("The token never shows in a description")
    func tokenStaysOutOfDescriptions() {
        let handoff = MusicTokenHandoff(requestID: UUID(), memberID: UUID(), userToken: "secret-token")
        #expect(!String(describing: handoff).contains("secret-token"))
        #expect(!String(reflecting: handoff).contains("secret-token"))
    }
}

@Suite("Apple Music proof and share books")
struct AppleMusicBookTests {
    let kyle = UUID()
    let sam = UUID()
    let start = Date(timeIntervalSince1970: 1_000_000)

    @Test("The HomePad takes a token only on the proof's session, for its member, once, in time")
    func proofBookRules() {
        var book = AppleMusicProofBook()
        let session = AppleMusicProofBook.Session(peerID: "phone", sessionID: UUID())
        let other = AppleMusicProofBook.Session(peerID: "phone", sessionID: UUID())
        let request = MusicShareRequest(memberID: kyle)
        let token = MusicTokenHandoff(requestID: request.requestID, memberID: kyle, userToken: "t")
        let forSam = MusicTokenHandoff(requestID: request.requestID, memberID: sam, userToken: "t")

        let wrongMember = book.issue(MusicShareRequest(memberID: sam), on: session, linkedMemberID: kyle, isMember: true, now: start)
        let notLinked = book.issue(request, on: session, linkedMemberID: nil, isMember: true, now: start)
        let gone = book.issue(request, on: session, linkedMemberID: kyle, isMember: false, now: start)
        #expect(refusal(wrongMember) == .notLinked)
        #expect(refusal(notLinked) == .notLinked)
        #expect(refusal(gone) == .notMember)

        _ = book.issue(request, on: session, linkedMemberID: kyle, isMember: true, now: start)
        let otherSession = book.accept(token, on: other, linkedMemberID: kyle, now: start)
        _ = book.issue(request, on: session, linkedMemberID: kyle, isMember: true, now: start)
        let otherMember = book.accept(forSam, on: session, linkedMemberID: kyle, now: start)
        _ = book.issue(request, on: session, linkedMemberID: kyle, isMember: true, now: start)
        let late = book.accept(token, on: session, linkedMemberID: kyle, now: start.addingTimeInterval(31))
        _ = book.issue(request, on: session, linkedMemberID: kyle, isMember: true, now: start)
        let good = book.accept(token, on: session, linkedMemberID: kyle, now: start.addingTimeInterval(5))
        let twice = book.accept(token, on: session, linkedMemberID: kyle, now: start.addingTimeInterval(6))

        #expect(refusal(otherSession) == .expired)
        #expect(refusal(otherMember) == .expired)
        #expect(refusal(late) == .expired)
        #expect((try? good.get()) == kyle)
        #expect(refusal(twice) == .expired)
    }

    @Test("The phone trusts only the kept key, from the HomePad it asked, for the member it is linked to")
    func shareBookRules() throws {
        let key = P256.Signing.PrivateKey()
        let trust = AppleMusicShareBook.HomePadTrust(linkedMemberID: kyle, homePadKey: key.publicKey.rawRepresentation)
        func proof(_ request: MusicShareRequest, by signer: P256.Signing.PrivateKey = key) throws -> MusicShareProof {
            let bytes = MusicShareProof.signedBytes(requestID: request.requestID, nonce: request.nonce, memberID: request.memberID,
                                                    homePadID: "pad", phoneID: "phone")
            return MusicShareProof(requestID: request.requestID, signature: try signer.signature(for: bytes).rawRepresentation)
        }
        var book = AppleMusicShareBook()

        let request = book.begin(homePadID: "pad", memberID: kyle, now: start)
        let good = try proof(request)
        // From another device: refused, and the request stays open for the real HomePad.
        let fromImpostor = book.verify(good, from: "impostor", phoneID: "phone", trust: trust, now: start)
        let fromPad = book.verify(good, from: "pad", phoneID: "phone", trust: trust, now: start)
        let replayed = book.verify(good, from: "pad", phoneID: "phone", trust: trust, now: start)
        #expect(refusal(fromImpostor) == .expired)
        #expect((try? fromPad.get()) == kyle)
        #expect(refusal(replayed) == .expired)

        let second = book.begin(homePadID: "pad", memberID: kyle, now: start)
        let forged = book.verify(try proof(second, by: P256.Signing.PrivateKey()), from: "pad", phoneID: "phone", trust: trust, now: start)
        #expect(refusal(forged) == .notVerified)

        let third = book.begin(homePadID: "pad", memberID: kyle, now: start)
        var relinked = trust
        relinked.linkedMemberID = sam
        let afterRelink = book.verify(try proof(third), from: "pad", phoneID: "phone", trust: relinked, now: start)
        #expect(refusal(afterRelink) == .notLinked)
    }

    private func refusal<Value>(_ result: Result<Value, MusicShareRefusal>) -> MusicShareRefusal? {
        if case .failure(let reason) = result { return reason }
        return nil
    }
}
