import Foundation

/// On a HomePad: which token handoffs it will take. A pure state machine with
/// no sockets or Keychain, so every rule is unit tested.
///
/// A phone earns a handoff in two steps on one sealed session. Its share
/// request, for the member it is linked to here, gets the HomePad's signed
/// proof. The token that follows counts only on that same session, for that
/// same member, once, within `AppleMusicLinkPolicy.proofLifetime`.
struct AppleMusicProofBook {
    /// Whose request it is: the device ID and the session it came in on.
    struct Session: Hashable {
        var peerID: String
        var sessionID: UUID
    }

    private struct Pending {
        var session: Session
        var memberID: UUID
        var issuedAt: Date
    }

    private var pending: [UUID: Pending] = [:]

    /// Takes a share request from a device linked to `linkedMemberID` here.
    /// The HomePad signs a proof only for the member the device is linked to.
    mutating func issue(_ request: MusicShareRequest, on session: Session, linkedMemberID: UUID?,
                        isMember: Bool, now: Date) -> Result<Void, MusicShareRefusal> {
        prune(now: now)
        guard isMember else { return .failure(.notMember) }
        guard let linkedMemberID, linkedMemberID == request.memberID else { return .failure(.notLinked) }
        pending[request.requestID] = Pending(session: session, memberID: request.memberID, issuedAt: now)
        return .success(())
    }

    /// Checks a token against the proof it follows. Returns the member it is for.
    mutating func accept(_ handoff: MusicTokenHandoff, on session: Session, linkedMemberID: UUID?,
                         now: Date) -> Result<UUID, MusicShareRefusal> {
        prune(now: now)
        guard let proof = pending.removeValue(forKey: handoff.requestID), proof.session == session,
              proof.memberID == handoff.memberID else { return .failure(.expired) }
        // The link may have changed between the proof and the token.
        guard linkedMemberID == proof.memberID else { return .failure(.notLinked) }
        let token = handoff.userToken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty, token.count <= AppleMusicLinkPolicy.maxTokenLength, token == handoff.userToken else {
            return .failure(.badToken)
        }
        return .success(proof.memberID)
    }

    /// Ends every open proof of a device whose session closed.
    mutating func revoke(peerID: String) {
        pending = pending.filter { $0.value.session.peerID != peerID }
    }

    private mutating func prune(now: Date) {
        pending = pending.filter { now.timeIntervalSince($0.value.issuedAt) < AppleMusicLinkPolicy.proofLifetime }
    }
}
