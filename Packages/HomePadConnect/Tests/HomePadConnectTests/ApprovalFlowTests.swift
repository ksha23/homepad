import CryptoKit
import Foundation
import HomePadCore
import Testing
@testable import HomePadConnect

/// Use Personal Device from the gate's side to the phone and back, through
/// the HomePad's approver and the phone's responder, in memory.
@MainActor
@Suite struct ApprovalFlowTests {
    // MARK: Linking

    @Test func thereIsNoPersonalDeviceUntilAPhoneIsLinked() async throws {
        let loop = ApprovalLoop()
        #expect(loop.approver.approvingDeviceName(for: loop.kyle.id) == nil)
        let outcome = await loop.approver.requestApproval(for: loop.kyle.id, appID: "messages", appTitle: "Messages")
        #expect(outcome == .unavailable("No personal device is set up for this person."))
        #expect(loop.sent(.approvalRequest).isEmpty)

        try await loop.linkPhone(to: loop.kyle)
        #expect(loop.approver.approvingDeviceName(for: loop.kyle.id) == "Kyle's iPhone")
        #expect(loop.approver.approvingDeviceName(for: loop.sam.id) == nil)
        #expect(loop.phone.linkedMember(on: loop.pad.id) == loop.kyle.id)
    }

    @Test func aLinkWaitsForSomeoneAtTheHomePad() async throws {
        let loop = ApprovalLoop()
        await loop.phone.requestState(of: loop.pad.id)
        await loop.settle()
        let kyle = try #require(loop.phone.states[loop.pad.id]?.members.first { $0.name == "Kyle" })
        await loop.phone.linkMember(kyle, on: loop.pad.id)
        await loop.settle()
        // Asking is not enough: nothing is linked until it is allowed on the HomePad.
        let pending = try #require(loop.approver.pendingLinks.first)
        #expect(pending.deviceName == "Kyle's iPhone")
        #expect(loop.approver.store.devices.isEmpty)
        #expect(loop.phone.states[loop.pad.id]?.pendingMemberID == kyle.id)

        // Kyle is not recognized at the HomePad, so the iPad asks its owner, who fails.
        loop.ownerPasses = false
        await loop.approver.allow(pending)
        #expect(loop.ownerAsked == 1)
        #expect(loop.approver.store.devices.isEmpty)

        loop.ownerPasses = true
        await loop.approver.allow(pending)
        await loop.settle()
        #expect(loop.approver.store.devices.map(\.memberID) == [kyle.id])
        #expect(loop.phone.states[loop.pad.id]?.linkedMemberID == kyle.id)
        #expect(loop.phone.states[loop.pad.id]?.pendingMemberID == nil)
    }

    @Test func theMemberRecognizedAtTheHomePadAllowsWithoutFaceID() async throws {
        let loop = ApprovalLoop()
        loop.padServices.household.recognize(loop.kyle.id)
        try await loop.linkPhone(to: loop.kyle)
        #expect(loop.ownerAsked == 0)
        #expect(loop.approver.store.devices.count == 1)
    }

    @Test func someoneElseRecognizedStillNeedsTheOwner() async throws {
        let loop = ApprovalLoop()
        loop.padServices.household.recognize(loop.sam.id)
        try await loop.linkPhone(to: loop.kyle)
        #expect(loop.ownerAsked == 1)
    }

    @Test func aDeclinedLinkSaysSo() async throws {
        let loop = ApprovalLoop()
        await loop.phone.requestState(of: loop.pad.id)
        await loop.settle()
        let kyle = try #require(loop.phone.states[loop.pad.id]?.members.first)
        await loop.phone.linkMember(kyle, on: loop.pad.id)
        await loop.settle()
        loop.approver.decline(try #require(loop.approver.pendingLinks.first))
        await loop.settle()
        #expect(loop.approver.store.devices.isEmpty)
        #expect(loop.phone.linkErrors[loop.pad.id] == "Kitchen didn't allow it.")
    }

    @Test func stoppingRemovesTheLink() async throws {
        let loop = ApprovalLoop()
        try await loop.linkPhone(to: loop.kyle)
        await loop.phone.linkMember(nil, on: loop.pad.id)
        await loop.settle()
        #expect(loop.approver.store.devices.isEmpty)
        #expect(loop.phone.linkedMember(on: loop.pad.id) == nil)
        #expect(loop.approver.approvingDeviceName(for: loop.kyle.id) == nil)
    }

    @Test func removingAMemberDropsTheirPhone() async throws {
        let loop = ApprovalLoop()
        try await loop.linkPhone(to: loop.kyle)
        loop.padServices.household.remove(loop.kyle.id)
        loop.approver.pruneLinks()
        #expect(loop.approver.store.devices.isEmpty)
    }

    // MARK: Approving

    @Test func approvingOnThePhoneLetsTheGateIn() async throws {
        let loop = ApprovalLoop()
        try await loop.linkPhone(to: loop.kyle)
        async let outcome = loop.approver.requestApproval(for: loop.kyle.id, appID: "messages", appTitle: "Messages")
        await loop.settle()
        let prompt = try #require(loop.phone.prompt)
        #expect(prompt.request.appTitle == "Messages")
        #expect(prompt.request.homePadName == "Kitchen")
        #expect(prompt.memberName == "Kyle")
        await loop.phone.approve()
        #expect(await outcome == .approved)
        #expect(loop.phone.prompt == nil)
    }

    @Test func aDenialOnThePhoneShowsOnTheHomePad() async throws {
        let loop = ApprovalLoop()
        try await loop.linkPhone(to: loop.kyle)
        async let outcome = loop.approver.requestApproval(for: loop.kyle.id, appID: "messages", appTitle: "Messages")
        await loop.settle()
        await loop.phone.deny()
        #expect(await outcome == .denied)
    }

    @Test func aRequestNobodyAnswersExpires() async throws {
        let loop = ApprovalLoop()
        try await loop.linkPhone(to: loop.kyle)
        loop.approver.requestLifetime = 0.2
        let outcome = await loop.approver.requestApproval(for: loop.kyle.id, appID: "messages", appTitle: "Messages")
        #expect(outcome == .expired)
        await loop.settle()
        // The phone is told to put its prompt away.
        #expect(loop.sent(.approvalClosed).count == 1)
        #expect(loop.phone.prompt == nil)
    }

    @Test func anApprovalAfterThirtySecondsIsTooLate() async throws {
        let loop = ApprovalLoop()
        try await loop.linkPhone(to: loop.kyle)
        async let outcome = loop.approver.requestApproval(for: loop.kyle.id, appID: "messages", appTitle: "Messages")
        await loop.settle()
        let request = try loop.lastRequest()
        // The HomePad's clock passes the request's end before the answer arrives.
        loop.padClock = loop.padClock.addingTimeInterval(31)
        let signature = try loop.phoneKey.signature(for: request.signedBytes(for: .approve)).rawRepresentation
        let late = try loop.phoneLink.message(.approvalResponse, ApprovalResponse(requestID: request.id, decision: .approve, signature: signature))
        loop.toPad(late, from: loop.phoneDevice)
        #expect(await outcome == .expired)
        #expect(loop.approver.lastRejection == .expired)
    }

    @Test func thePhoneDoesNotApproveAfterItsOwnDeadline() async throws {
        let loop = ApprovalLoop()
        try await loop.linkPhone(to: loop.kyle)
        loop.approver.requestLifetime = 1
        async let outcome = loop.approver.requestApproval(for: loop.kyle.id, appID: "messages", appTitle: "Messages")
        await loop.settle()
        #expect(loop.phone.prompt != nil)
        loop.phoneClock = loop.phoneClock.addingTimeInterval(2)
        await loop.phone.approve()
        #expect(loop.phone.prompt == nil)
        #expect(loop.sent(.approvalResponse).isEmpty)
        #expect(await outcome == .expired)
    }

    @Test func aReplayedApprovalUnlocksNothing() async throws {
        let loop = ApprovalLoop()
        try await loop.linkPhone(to: loop.kyle)
        async let first = loop.approver.requestApproval(for: loop.kyle.id, appID: "messages", appTitle: "Messages")
        await loop.settle()
        await loop.phone.approve()
        #expect(await first == .approved)
        let recorded = try #require(loop.sent(.approvalResponse).last)

        // A second request, answered with the recorded approval of the first.
        loop.approver.requestLifetime = 0.3
        async let second = loop.approver.requestApproval(for: loop.kyle.id, appID: "messages", appTitle: "Messages")
        await loop.settle()
        loop.toPad(recorded, from: loop.phoneDevice)
        #expect(loop.approver.lastRejection == .replayed)
        #expect(await second == .expired)
    }

    @Test func anotherMembersPhoneCannotAnswer() async throws {
        let loop = ApprovalLoop()
        try await loop.linkPhone(to: loop.kyle)
        // Sam's phone is linked to Sam with its own key.
        let samKey = P256.Signing.PrivateKey()
        loop.approver.store.save(LinkedDevice(
            id: "phone-sam", name: "Sam's iPhone", kind: .iPhone, memberID: loop.sam.id,
            publicKey: samKey.publicKey.rawRepresentation, remoteVersion: RemoteProtocol.current, linkedAt: loop.padClock
        ))
        loop.approver.requestLifetime = 0.3
        async let outcome = loop.approver.requestApproval(for: loop.kyle.id, appID: "messages", appTitle: "Messages")
        await loop.settle()
        let request = try loop.lastRequest()
        // Only Kyle's phone was asked.
        #expect(loop.sent(.approvalRequest).count == 1)
        let signature = try samKey.signature(for: request.signedBytes(for: .approve)).rawRepresentation
        let answer = try loop.phoneLink.message(.approvalResponse, ApprovalResponse(requestID: request.id, decision: .approve, signature: signature))
        let samsPhone = PeerDevice(id: "phone-sam", name: "iPhone", kind: .iPhone, isConnected: true)
        loop.toPad(answer, from: samsPhone)
        #expect(loop.approver.lastRejection == .wrongDevice)
        #expect(await outcome == .expired)
    }

    @Test func anUnreachablePhoneSaysSo() async throws {
        let loop = ApprovalLoop()
        try await loop.linkPhone(to: loop.kyle)
        loop.unreachable = [loop.phoneDevice.id]
        let outcome = await loop.approver.requestApproval(for: loop.kyle.id, appID: "messages", appTitle: "Messages")
        #expect(outcome == .unavailable("Kyle's iPhone isn't reachable. Open HomePad on it, then try again."))
    }

    @Test func closingTheGateWithdrawsTheRequest() async throws {
        let loop = ApprovalLoop()
        try await loop.linkPhone(to: loop.kyle)
        let task = Task { await loop.approver.requestApproval(for: loop.kyle.id, appID: "messages", appTitle: "Messages") }
        await loop.settle()
        #expect(loop.phone.prompt != nil)
        task.cancel()
        #expect(await task.value == .unavailable("Cancelled."))
        await loop.settle()
        #expect(loop.phone.prompt == nil)
        // Approving now is too late: the request is closed on the HomePad.
        #expect(loop.sent(.approvalClosed).count == 1)
    }

    // MARK: The phone's checks

    @Test func thePhoneIgnoresRequestsForSomeoneElse() async throws {
        let loop = ApprovalLoop()
        try await loop.linkPhone(to: loop.kyle)
        let forSam = ApprovalRequest(memberID: loop.sam.id, homePadID: loop.pad.id, homePadName: "Kitchen", appID: "messages", appTitle: "Messages")
        loop.toPhone(try loop.padLink.message(.approvalRequest, forSam))
        #expect(loop.phone.prompt == nil)
    }

    @Test func thePhoneIgnoresARequestNamingAnotherHomePad() async throws {
        let loop = ApprovalLoop()
        try await loop.linkPhone(to: loop.kyle)
        let elsewhere = ApprovalRequest(memberID: loop.kyle.id, homePadID: "pad-bedroom", homePadName: "Bedroom", appID: "messages", appTitle: "Messages")
        loop.toPhone(try loop.padLink.message(.approvalRequest, elsewhere))
        #expect(loop.phone.prompt == nil)
    }

    @Test func thePhoneShowsARequestOnce() async throws {
        let loop = ApprovalLoop()
        try await loop.linkPhone(to: loop.kyle)
        let request = ApprovalRequest(memberID: loop.kyle.id, homePadID: loop.pad.id, homePadName: "Kitchen", appID: "messages", appTitle: "Messages")
        let message = try loop.padLink.message(.approvalRequest, request)
        loop.toPhone(message)
        #expect(loop.phone.prompt?.id == request.id)
        await loop.phone.deny()
        loop.toPhone(message)
        #expect(loop.phone.prompt == nil)
    }

    @Test func anUnlinkedPhoneShowsNothing() async throws {
        let loop = ApprovalLoop()
        let request = ApprovalRequest(memberID: loop.kyle.id, homePadID: loop.pad.id, homePadName: "Kitchen", appID: "messages", appTitle: "Messages")
        loop.toPhone(try loop.padLink.message(.approvalRequest, request))
        #expect(loop.phone.prompt == nil)
    }

    // MARK: Versions

    @Test func onlyHomePadsThatSpeakVersionThreeOfferIt() throws {
        func status(_ version: Int?) -> HomePadStatus { HomePadStatus(deviceID: "pad", name: "Kitchen", remoteVersion: version) }
        #expect(!status(nil).supportsPersonalDevices)
        #expect(!status(RemoteProtocol.music).supportsPersonalDevices)
        #expect(status(RemoteProtocol.personalDevices).supportsPersonalDevices)
        #expect(RemoteProtocol.current >= RemoteProtocol.personalDevices)
    }

    @Test func aDeviceThatLinkedWithAnOlderVersionGetsNoButton() async throws {
        let loop = ApprovalLoop()
        loop.approver.store.save(LinkedDevice(
            id: "phone-old", name: "Kyle's iPhone", kind: .iPhone, memberID: loop.kyle.id,
            publicKey: P256.Signing.PrivateKey().publicKey.rawRepresentation, remoteVersion: RemoteProtocol.music,
            linkedAt: loop.padClock
        ))
        #expect(loop.approver.approvingDeviceName(for: loop.kyle.id) == nil)
    }
}
