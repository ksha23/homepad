import Foundation

/// On a phone: which HomePad may receive the person's Music User Token. A
/// pure state machine with no sockets or MusicKit, so every rule is unit tested.
///
/// The phone sends a fresh nonce, and the token goes only to the HomePad that
/// signs it with the key the phone kept when it linked, on the session that
/// signature came in on, for the member the phone is linked to there. Another
/// household device can say it is the HomePad, but it cannot make that signature.
struct AppleMusicShareBook {
    /// What the phone knows about the HomePad that answers.
    struct HomePadTrust {
        /// The member this phone is linked to on that HomePad.
        var linkedMemberID: UUID?
        /// The HomePad's public key, kept when the phone linked.
        var homePadKey: Data?
    }

    private struct Pending {
        var homePadID: String
        var memberID: UUID
        var nonce: Data
        var issuedAt: Date
    }

    private var pending: [UUID: Pending] = [:]

    /// A share request for one HomePad, with a fresh nonce.
    mutating func begin(homePadID: String, memberID: UUID, now: Date) -> MusicShareRequest {
        prune(now: now)
        let request = MusicShareRequest(memberID: memberID)
        pending[request.requestID] = Pending(homePadID: homePadID, memberID: memberID, nonce: request.nonce, issuedAt: now)
        return request
    }

    /// Checks the HomePad's proof. Returns the member the token is for. Each
    /// request is answered once, by the HomePad it was sent to, within its lifetime.
    mutating func verify(_ proof: MusicShareProof, from homePadID: String, phoneID: String, trust: HomePadTrust,
                         now: Date) -> Result<UUID, MusicShareRefusal> {
        prune(now: now)
        // A proof from another device leaves the request open for the real HomePad.
        guard let request = pending[proof.requestID], request.homePadID == homePadID else { return .failure(.expired) }
        pending[proof.requestID] = nil
        // The link may have changed while the request was out.
        guard trust.linkedMemberID == request.memberID else { return .failure(.notLinked) }
        guard let key = trust.homePadKey else { return .failure(.notVerified) }
        let signed = MusicShareProof.signedBytes(requestID: proof.requestID, nonce: request.nonce, memberID: request.memberID,
                                                 homePadID: homePadID, phoneID: phoneID)
        guard HomePadKey.isValid(proof.signature, of: signed, by: key) else { return .failure(.notVerified) }
        return .success(request.memberID)
    }

    /// Forgets a request that ended another way, such as a refusal.
    mutating func cancel(_ requestID: UUID) {
        pending[requestID] = nil
    }

    /// True while a request to that HomePad waits for its proof.
    func isWaiting(for homePadID: String, now: Date) -> Bool {
        pending.values.contains { $0.homePadID == homePadID && now.timeIntervalSince($0.issuedAt) < AppleMusicLinkPolicy.proofLifetime }
    }

    private mutating func prune(now: Date) {
        pending = pending.filter { now.timeIntervalSince($0.value.issuedAt) < AppleMusicLinkPolicy.proofLifetime }
    }
}
