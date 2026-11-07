import CryptoKit
import Foundation
import Testing
@testable import HomePadConnect

@Suite struct PairingSecurityTests {
    private let kitchen = LocalIdentity(deviceID: "pad-kitchen", name: "Kitchen", kind: .homePad)
    private let phone = LocalIdentity(deviceID: "phone-kyle", name: "Kyle's iPhone", kind: .iPhone)
    private let household = HouseholdCredentials(name: "Home")

    /// Runs two engines against each other until neither has anything to send.
    private func run(_ initiator: inout HandshakeEngine, _ responder: inout HandshakeEngine) throws -> (i: [HandshakeEngine.Step], r: [HandshakeEngine.Step]) {
        var toResponder = try initiator.start().compactMap(\.message)
        var initiatorSteps: [HandshakeEngine.Step] = []
        var responderSteps: [HandshakeEngine.Step] = []
        while !toResponder.isEmpty {
            var toInitiator: [PeerMessage] = []
            for message in toResponder {
                let steps = try responder.receive(roundTrip(message))
                responderSteps += steps
                toInitiator += steps.compactMap(\.message)
            }
            toResponder = []
            for message in toInitiator {
                let steps = try initiator.receive(roundTrip(message))
                initiatorSteps += steps
                toResponder += steps.compactMap(\.message)
            }
        }
        return (initiatorSteps, responderSteps)
    }

    private func roundTrip(_ message: PeerMessage) throws -> PeerMessage {
        try MessageCodec.decode(MessageCodec.encode(message))
    }

    @Test func sessionHandshakeDerivesMatchingChannels() throws {
        var i = HandshakeEngine(role: .initiator, local: phone, intent: .session, credentials: household)
        var r = HandshakeEngine(role: .responder, local: kitchen, intent: .session, credentials: household)
        let result = try run(&i, &r)

        guard var phoneChannel = result.i.compactMap(\.channel).first,
              var padChannel = result.r.compactMap(\.channel).first else {
            Issue.record("both sides should be established")
            return
        }
        #expect(i.isComplete && r.isComplete)
        #expect(i.peerHello?.name == "Kitchen")
        #expect(r.peerHello?.kind == .iPhone)

        let sealed = try phoneChannel.seal(Data("hello kitchen".utf8))
        #expect(try padChannel.open(sealed) == Data("hello kitchen".utf8))
        let reply = try padChannel.seal(Data("hi phone".utf8))
        #expect(try phoneChannel.open(reply) == Data("hi phone".utf8))
    }

    @Test func wrongHouseholdKeyFailsTheProof() throws {
        var impostorHousehold = HouseholdCredentials(name: "Home")
        impostorHousehold.id = household.id   // knows the public ID, not the key
        var i = HandshakeEngine(role: .initiator, local: phone, intent: .session, credentials: impostorHousehold)
        var r = HandshakeEngine(role: .responder, local: kitchen, intent: .session, credentials: household)
        #expect(throws: HandshakeError.badProof) { _ = try run(&i, &r) }
    }

    @Test func differentHouseholdIsTurnedAwayBeforeAnyProof() throws {
        var i = HandshakeEngine(role: .initiator, local: phone, intent: .session, credentials: HouseholdCredentials(name: "Other"))
        var r = HandshakeEngine(role: .responder, local: kitchen, intent: .session, credentials: household)
        #expect(throws: HandshakeError.wrongHousehold) { _ = try run(&i, &r) }
    }

    @Test func pairingWithTheRightCodeSharesTheHousehold() throws {
        var i = HandshakeEngine(role: .initiator, local: phone, intent: .pair, credentials: nil, pairingCode: "482913")
        var r = HandshakeEngine(role: .responder, local: kitchen, intent: .session, credentials: household, pairingCode: "482913")
        let result = try run(&i, &r)

        let joined = result.i.compactMap { step -> HouseholdCredentials? in
            if case .joined(let credentials, _) = step { return credentials }
            return nil
        }
        #expect(joined == [household])
        #expect(result.r.contains { if case .admitted = $0 { true } else { false } })
    }

    @Test func pairingWithTheWrongCodeIsRejected() throws {
        var i = HandshakeEngine(role: .initiator, local: phone, intent: .pair, credentials: nil, pairingCode: "000000")
        var r = HandshakeEngine(role: .responder, local: kitchen, intent: .session, credentials: household, pairingCode: "482913")
        #expect(throws: HandshakeError.wrongCode) { _ = try run(&i, &r) }
    }

    @Test func pairingIsRefusedWhenNoWindowIsOpen() throws {
        var i = HandshakeEngine(role: .initiator, local: phone, intent: .pair, credentials: nil, pairingCode: "482913")
        var r = HandshakeEngine(role: .responder, local: kitchen, intent: .session, credentials: household, pairingCode: nil)
        #expect(throws: HandshakeError.pairingClosed) { _ = try run(&i, &r) }
    }

    @Test func pairingKeysDependOnCodeAndAreDeterministic() throws {
        let a = Curve25519.KeyAgreement.PrivateKey()
        let b = Curve25519.KeyAgreement.PrivateKey()
        let sharedA = try a.sharedSecretFromKeyAgreement(with: b.publicKey)
        let sharedB = try b.sharedSecretFromKeyAgreement(with: a.publicKey)
        let transcript = Data("transcript".utf8)

        let keysA = KeySchedule.pairingKeys(code: "123456", sharedSecret: sharedA, transcript: transcript)
        let keysB = KeySchedule.pairingKeys(code: "123456", sharedSecret: sharedB, transcript: transcript)
        let wrong = KeySchedule.pairingKeys(code: "123457", sharedSecret: sharedB, transcript: transcript)

        let proof = KeySchedule.proof(key: keysA.auth, transcript: transcript, role: .initiator)
        #expect(KeySchedule.verify(proof, key: keysB.auth, transcript: transcript, role: .initiator))
        #expect(!KeySchedule.verify(proof, key: wrong.auth, transcript: transcript, role: .initiator))
        // A proof cannot be reflected back as the other role's proof.
        #expect(!KeySchedule.verify(proof, key: keysB.auth, transcript: transcript, role: .responder))

        let sealed = try KeySchedule.sealHousehold(household, with: keysA.seal)
        #expect(try KeySchedule.openHousehold(sealed, with: keysB.seal) == household)
        #expect(throws: (any Error).self) { try KeySchedule.openHousehold(sealed, with: wrong.seal) }
    }

    @Test func secureChannelRejectsReplayAndTampering() throws {
        let k1 = SymmetricKey(size: .bits256)
        let k2 = SymmetricKey(size: .bits256)
        var sender = SecureChannel(sendKey: k1, receiveKey: k2)
        var receiver = SecureChannel(sendKey: k2, receiveKey: k1)

        let first = try sender.seal(Data("one".utf8))
        let second = try sender.seal(Data("two".utf8))
        #expect(try receiver.open(first) == Data("one".utf8))
        #expect(throws: SecureChannelError.replayedOrOutOfOrder) { try receiver.open(first) }

        var tampered = second
        tampered[tampered.count - 1] ^= 0xFF
        #expect(throws: (any Error).self) { try receiver.open(tampered) }
        #expect(try receiver.open(second) == Data("two".utf8))
    }

    @Test func pairingCodesAreSixDigits() {
        for _ in 0..<200 {
            let code = PairingCode.generate()
            #expect(code.count == 6)
            #expect(PairingCode.normalize(code) == code)
        }
        #expect(PairingCode.normalize("482 913") == "482913")
        #expect(PairingCode.normalize("482-913") == "482913")
        #expect(PairingCode.normalize("48291") == nil)
        #expect(PairingCode.normalize("48291a") == nil)
        #expect(PairingCode.formatted("482913") == "482 913")
    }

    @Test func pairingWindowClosesAfterTooManyGuesses() {
        var window = PairingWindow(code: "111111", expiresAt: Date().addingTimeInterval(60))
        #expect(window.isOpen())
        window.failedAttempts = PairingCode.maxAttempts
        #expect(!window.isOpen())
        #expect(!PairingWindow(expiresAt: Date().addingTimeInterval(-1)).isOpen())
    }
}

private extension HandshakeEngine.Step {
    var message: PeerMessage? {
        if case .send(let message) = self { return message }
        return nil
    }

    var channel: SecureChannel? {
        if case .established(let channel, _) = self { return channel }
        return nil
    }
}
