import CryptoKit
import Foundation
import Testing
@testable import HomePadConnect

/// The checks every answer to an approval request must pass on the HomePad.
@Suite struct ApprovalLedgerTests {
    private let kyle = UUID()
    private let sam = UUID()
    private let kyleKey = P256.Signing.PrivateKey()
    private let samKey = P256.Signing.PrivateKey()
    private let start = Date(timeIntervalSince1970: 1_800_000_000)

    private var devices: [LinkedDevice] {
        [device("phone-kyle", member: kyle, key: kyleKey), device("phone-sam", member: sam, key: samKey)]
    }

    private func device(_ id: String, member: UUID, key: P256.Signing.PrivateKey,
                        version: Int = RemoteProtocol.personalDevices) -> LinkedDevice {
        LinkedDevice(id: id, name: id, kind: .iPhone, memberID: member, publicKey: key.publicKey.rawRepresentation,
                     remoteVersion: version, linkedAt: start)
    }

    private func request(for member: UUID, appTitle: String = "Messages") -> ApprovalRequest {
        ApprovalRequest(memberID: member, homePadID: "pad-kitchen", homePadName: "Kitchen", appID: "messages", appTitle: appTitle)
    }

    private func approval(_ request: ApprovalRequest, key: P256.Signing.PrivateKey) throws -> ApprovalResponse {
        let signature = try key.signature(for: request.signedBytes(for: .approve)).rawRepresentation
        return ApprovalResponse(requestID: request.id, decision: .approve, signature: signature)
    }

    @Test func approvesWithTheLinkedDevicesSignature() throws {
        var ledger = ApprovalLedger()
        let request = request(for: kyle)
        ledger.issue(request, now: start)
        let verdict = ledger.verify(try approval(request, key: kyleKey), from: "phone-kyle", devices: devices,
                                    now: start.addingTimeInterval(5))
        #expect(verdict == .approved(request))
        #expect(!ledger.isOpen(request.id))
    }

    @Test func aRepeatedApprovalIsAReplay() throws {
        var ledger = ApprovalLedger()
        let request = request(for: kyle)
        ledger.issue(request, now: start)
        let answer = try approval(request, key: kyleKey)
        #expect(ledger.verify(answer, from: "phone-kyle", devices: devices, now: start) == .approved(request))
        #expect(ledger.verify(answer, from: "phone-kyle", devices: devices, now: start) == .rejected(.replayed))
    }

    @Test func anAnswerAfterThirtySecondsHasExpired() throws {
        var ledger = ApprovalLedger()
        let request = request(for: kyle)
        #expect(request.lifetime == 30)
        ledger.issue(request, now: start)
        let answer = try approval(request, key: kyleKey)
        #expect(ledger.verify(answer, from: "phone-kyle", devices: devices, now: start.addingTimeInterval(30)) == .rejected(.expired))
        // Expired requests stay closed: the same answer later is a replay.
        #expect(ledger.verify(answer, from: "phone-kyle", devices: devices, now: start.addingTimeInterval(31)) == .rejected(.replayed))
    }

    @Test func anAnswerJustInsideTheLifetimeCounts() throws {
        var ledger = ApprovalLedger()
        let request = request(for: kyle)
        ledger.issue(request, now: start)
        let verdict = ledger.verify(try approval(request, key: kyleKey), from: "phone-kyle", devices: devices,
                                    now: start.addingTimeInterval(29.9))
        #expect(verdict == .approved(request))
    }

    @Test func anotherMembersPhoneCannotApprove() throws {
        var ledger = ApprovalLedger()
        let request = request(for: kyle)
        ledger.issue(request, now: start)
        // Sam's phone, signing with Sam's own key, answering Kyle's request.
        #expect(ledger.verify(try approval(request, key: samKey), from: "phone-sam", devices: devices, now: start) == .rejected(.wrongDevice))
        // Or denying it.
        let denial = ApprovalResponse(requestID: request.id, decision: .deny)
        #expect(ledger.verify(denial, from: "phone-sam", devices: devices, now: start) == .rejected(.wrongDevice))
        // Kyle's request is still open for Kyle's phone.
        #expect(ledger.isOpen(request.id))
        #expect(ledger.verify(try approval(request, key: kyleKey), from: "phone-kyle", devices: devices, now: start) == .approved(request))
    }

    @Test func aDeviceClaimingThePhonesIDCannotSignForIt() throws {
        var ledger = ApprovalLedger()
        let request = request(for: kyle)
        ledger.issue(request, now: start)
        // Any household device can say it is phone-kyle, but it lacks the key.
        let forged = try approval(request, key: samKey)
        #expect(ledger.verify(forged, from: "phone-kyle", devices: devices, now: start) == .rejected(.badSignature))
        let unsigned = ApprovalResponse(requestID: request.id, decision: .approve)
        #expect(ledger.verify(unsigned, from: "phone-kyle", devices: devices, now: start) == .rejected(.badSignature))
        #expect(ledger.isOpen(request.id))
    }

    @Test func aSignatureFitsOnlyItsRequest() throws {
        var ledger = ApprovalLedger()
        let first = request(for: kyle)
        let second = request(for: kyle)
        ledger.issue(first, now: start)
        ledger.issue(second, now: start)
        // An approval of the first request, sent as an answer to the second.
        var moved = try approval(first, key: kyleKey)
        moved.requestID = second.id
        #expect(ledger.verify(moved, from: "phone-kyle", devices: devices, now: start) == .rejected(.badSignature))
    }

    @Test func theSignatureCoversWhatThePhoneShowed() throws {
        let request = request(for: kyle, appTitle: "Messages")
        var shown = request
        shown.appTitle = "Timers"
        #expect(request.signedBytes(for: .approve) != shown.signedBytes(for: .approve))
        #expect(request.signedBytes(for: .approve) != request.signedBytes(for: .deny))
        var ledger = ApprovalLedger()
        ledger.issue(request, now: start)
        // The phone was shown "Timers" and approved that.
        #expect(ledger.verify(try approval(shown, key: kyleKey), from: "phone-kyle", devices: devices, now: start) == .rejected(.badSignature))
    }

    @Test func aDenialFromTheLinkedPhoneEndsTheRequest() throws {
        var ledger = ApprovalLedger()
        let request = request(for: kyle)
        ledger.issue(request, now: start)
        let denial = ApprovalResponse(requestID: request.id, decision: .deny)
        #expect(ledger.verify(denial, from: "phone-kyle", devices: devices, now: start) == .denied(request))
        #expect(ledger.verify(try approval(request, key: kyleKey), from: "phone-kyle", devices: devices, now: start) == .rejected(.replayed))
    }

    @Test func answersToUnknownOrWithdrawnRequestsAreDropped() throws {
        var ledger = ApprovalLedger()
        let never = request(for: kyle)
        #expect(ledger.verify(try approval(never, key: kyleKey), from: "phone-kyle", devices: devices, now: start) == .rejected(.unknownRequest))
        let withdrawn = request(for: kyle)
        ledger.issue(withdrawn, now: start)
        ledger.withdraw(withdrawn.id, now: start)
        #expect(ledger.verify(try approval(withdrawn, key: kyleKey), from: "phone-kyle", devices: devices, now: start) == .rejected(.replayed))
    }

    @Test func aDeviceLinkedBeforeApprovalCannotApprove() throws {
        var ledger = ApprovalLedger()
        let request = request(for: kyle)
        ledger.issue(request, now: start)
        let old = [device("phone-kyle", member: kyle, key: kyleKey, version: RemoteProtocol.music)]
        #expect(ledger.verify(try approval(request, key: kyleKey), from: "phone-kyle", devices: old, now: start) == .rejected(.wrongDevice))
    }

    @Test func requestsAndAnswersCrossTheWire() throws {
        let request = request(for: kyle)
        let message = try PeerMessage(type: .approvalRequest, sender: "pad-kitchen", content: request)
        let decoded = try MessageCodec.decode(MessageCodec.encode(message)).content(ApprovalRequest.self)
        #expect(decoded == request)
        #expect(decoded.signedBytes(for: .approve) == request.signedBytes(for: .approve))
        #expect(request.nonce.count == 32)
        #expect(ApprovalRequest(memberID: kyle, homePadID: "p", homePadName: "K", appID: "a", appTitle: "A").nonce != request.nonce)
    }
}
