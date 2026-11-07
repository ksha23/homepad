import CryptoKit
import Foundation

/// On a HomePad: the Spotify sign-ins phones are handing over, and the checks
/// each message must pass. No sockets, so it is tested.
///
/// A sign-in is taken only for the member the sending phone is linked to here
/// (`LinkedDeviceStore`), on the session its hello came on, within
/// `SpotifyHandoffPolicy.lifetime`, signed with that phone's approval key,
/// and sealed to this HomePad's one-time key. Each hello is used once. An
/// answer that fails leaves the request open, so a forged one cannot end it.
struct SpotifyHandoffBook {
    struct Session: Hashable {
        var peerID: String
        var sessionID: UUID
    }

    private struct Open {
        let hello: SpotifyHello
        let challenge: SpotifyChallenge
        let session: Session
        let agreementKey: Curve25519.KeyAgreement.PrivateKey
        let issuedAt: Date
    }

    private var open: [UUID: Open] = [:]

    /// A phone has a sign-in for `hello.memberID`. `linked` is the link of the
    /// device the session belongs to, `sign` signs with this HomePad's key.
    mutating func hello(_ hello: SpotifyHello, on session: Session, linked: LinkedDevice?, homePadID: String,
                        sign: (Data) throws -> Data, now: Date) -> Result<SpotifyChallenge, SpotifyRefusal> {
        open = open.filter { now.timeIntervalSince($0.value.issuedAt) <= SpotifyHandoffPolicy.lifetime }
        guard let linked, linked.memberID == hello.memberID else { return .failure(.notLinked) }
        guard open[hello.requestID] == nil, hello.nonce.count == 32,
              (try? Curve25519.KeyAgreement.PublicKey(rawRepresentation: hello.agreementKey)) != nil else {
            return .failure(.notVerified)
        }
        let key = SpotifyHandoffSeal.newAgreementKey()
        let nonce = ApprovalRequest.randomNonce()
        let agreementKey = key.publicKey.rawRepresentation
        let bytes = SpotifyChallenge.signedBytes(hello: hello, nonce: nonce, agreementKey: agreementKey,
                                                 homePadID: homePadID, phoneID: linked.id)
        guard let signature = try? sign(bytes) else { return .failure(.notVerified) }
        let challenge = SpotifyChallenge(requestID: hello.requestID, nonce: nonce, agreementKey: agreementKey, signature: signature)
        open[hello.requestID] = Open(hello: hello, challenge: challenge, session: session, agreementKey: key, issuedAt: now)
        return .success(challenge)
    }

    /// The phone's sealed sign-in. Gives the member it is for and Spotify's
    /// code once every check passes, and closes the request.
    mutating func handoff(_ handoff: SpotifyHandoff, on session: Session, linked: LinkedDevice?, homePadID: String,
                          now: Date) -> Result<(member: UUID, signIn: SpotifySignInCode), SpotifyRefusal> {
        guard let entry = open[handoff.requestID] else { return .failure(.expired) }
        guard now.timeIntervalSince(entry.issuedAt) <= SpotifyHandoffPolicy.lifetime else {
            open[handoff.requestID] = nil
            return .failure(.expired)
        }
        guard entry.session == session else { return .failure(.notVerified) }
        guard let linked, linked.id == session.peerID, linked.memberID == entry.hello.memberID else {
            return .failure(.notLinked)
        }
        let bytes = SpotifyHandoff.signedBytes(hello: entry.hello, challenge: entry.challenge, sealed: handoff.sealed,
                                               homePadID: homePadID, phoneID: linked.id)
        guard linked.signed(bytes, with: handoff.signature),
              let key = try? SpotifyHandoffSeal.key(privateKey: entry.agreementKey, peerKey: entry.hello.agreementKey,
                                                    hello: entry.hello, homePadNonce: entry.challenge.nonce),
              let signIn = try? SpotifyHandoffSeal.open(handoff.sealed, with: key, requestID: handoff.requestID) else {
            return .failure(.notVerified)
        }
        open[handoff.requestID] = nil
        return .success((entry.hello.memberID, signIn))
    }

    /// The device's session closed: what it opened ends with it.
    mutating func revoke(peerID: String) {
        open = open.filter { $0.value.session.peerID != peerID }
    }
}
