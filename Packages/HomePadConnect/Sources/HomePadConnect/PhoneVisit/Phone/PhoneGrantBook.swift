import Foundation

/// On a phone: which HomePad sessions may read which kinds of its owner's
/// data. A pure state machine with no sockets, PhotoKit or EventKit, so every
/// rule is unit tested.
///
/// A HomePad earns a grant in two steps on one sealed session. Its hello gets
/// a fresh nonce, and its signature over that nonce with the key the phone kept
/// when it linked opens the kinds the person shares with that HomePad, to that
/// session only. A new session with the same device ID, which any household
/// device could open, starts with nothing.
struct PhoneGrantBook {
    /// Whose request it is: the device ID and the session it came in on.
    struct Session: Hashable {
        var peerID: String
        var sessionID: UUID
    }

    /// What the phone knows about the HomePad that says hello.
    struct HomePadTrust {
        /// The member this phone is linked to on that HomePad.
        var linkedMemberID: UUID?
        /// The kinds the person shares with that HomePad.
        var sharing: Set<PhoneDataKind>
        /// The kinds HomePad on this phone may read: the photo library, Calendar, Reminders.
        var readable: Set<PhoneDataKind>
        /// The HomePad's public key, kept when the phone linked.
        var homePadKey: Data?
    }

    private struct Challenge {
        var session: Session
        var memberID: UUID
        var kinds: Set<PhoneDataKind>
        var nonce: Data
        var issuedAt: Date
    }

    private struct Grant {
        var memberID: UUID
        var kinds: Set<PhoneDataKind>
        var grantedAt: Date
    }

    private var challenges: [UUID: Challenge] = [:]
    private var grants: [Session: Grant] = [:]

    /// Answers a hello: a challenge to sign, or why not. The kinds it will
    /// open are the ones asked for that the person shares and HomePad can read.
    mutating func hello(_ hello: PhoneVisitHello, on session: Session, trust: HomePadTrust, now: Date) -> Result<PhoneVisitChallenge, PhoneVisitRefusal> {
        prune(now: now)
        guard let linked = trust.linkedMemberID, linked == hello.memberID else { return .failure(.notLinked) }
        let shared = hello.requestedKinds.intersection(trust.sharing)
        guard !shared.isEmpty else { return .failure(.notSharing) }
        let readable = shared.intersection(trust.readable)
        guard !readable.isEmpty else {
            // The first kind in a fixed order, so the reason is the same every time.
            let unreadable = PhoneDataKind.allCases.first(where: shared.contains) ?? .photos
            return .failure(.noAccess(to: unreadable))
        }
        guard trust.homePadKey != nil else { return .failure(.notVerified) }
        let challenge = PhoneVisitChallenge(requestID: hello.requestID)
        challenges[hello.requestID] = Challenge(session: session, memberID: hello.memberID, kinds: readable,
                                                nonce: challenge.nonce, issuedAt: now)
        return .success(challenge)
    }

    /// Checks the HomePad's signature and returns the kinds opened. A
    /// challenge is used once, on the session it was issued to, within its lifetime.
    mutating func open(_ open: PhoneVisitOpen, on session: Session, phoneID: String, trust: HomePadTrust, now: Date) -> Result<Set<PhoneDataKind>, PhoneVisitRefusal> {
        prune(now: now)
        guard let challenge = challenges.removeValue(forKey: open.requestID), challenge.session == session else {
            return .failure(.expired)
        }
        // The link or the sharing may have changed between the hello and the signature.
        let kinds = challenge.kinds.intersection(trust.sharing).intersection(trust.readable)
        guard trust.linkedMemberID == challenge.memberID, !kinds.isEmpty else { return .failure(.notLinked) }
        guard let key = trust.homePadKey else { return .failure(.notVerified) }
        let signed = PhoneVisitOpen.signedBytes(requestID: open.requestID, nonce: challenge.nonce, memberID: challenge.memberID,
                                                homePadID: session.peerID, phoneID: phoneID)
        guard HomePadKey.isValid(open.signature, of: signed, by: key) else { return .failure(.notVerified) }
        grants[session] = Grant(memberID: challenge.memberID, kinds: kinds, grantedAt: now)
        return .success(kinds)
    }

    /// True when this session may read `kind` of `memberID` right now.
    func isGranted(_ session: Session, memberID: UUID, kind: PhoneDataKind, now: Date) -> Bool {
        grantedMember(session, kind: kind, now: now) == memberID
    }

    /// The member a session was opened for, while its grant lasts and covers `kind`.
    func grantedMember(_ session: Session, kind: PhoneDataKind, now: Date) -> UUID? {
        guard let grant = grants[session], grant.kinds.contains(kind),
              now.timeIntervalSince(grant.grantedAt) < PhoneVisitPolicy.grantLifetime else { return nil }
        return grant.memberID
    }

    /// Ends one session's grant (the visit close).
    mutating func close(_ session: Session) {
        grants[session] = nil
        challenges = challenges.filter { $0.value.session != session }
    }

    /// Ends every grant and challenge of a device: it disconnected, stopped
    /// being linked, or the person stopped sharing with it.
    mutating func revoke(peerID: String) {
        grants = grants.filter { $0.key.peerID != peerID }
        challenges = challenges.filter { $0.value.session.peerID != peerID }
    }

    /// Takes one kind out of a device's grants, when the person stops sharing
    /// it but still shares others.
    mutating func revoke(_ kind: PhoneDataKind, peerID: String) {
        for (session, grant) in grants where session.peerID == peerID {
            var narrowed = grant
            narrowed.kinds.remove(kind)
            grants[session] = narrowed.kinds.isEmpty ? nil : narrowed
        }
    }

    /// True while some session may still ask.
    func hasOpenGrants(now: Date) -> Bool {
        grants.values.contains { now.timeIntervalSince($0.grantedAt) < PhoneVisitPolicy.grantLifetime }
    }

    private mutating func prune(now: Date) {
        challenges = challenges.filter { now.timeIntervalSince($0.value.issuedAt) < PhoneVisitPolicy.challengeLifetime }
        grants = grants.filter { now.timeIntervalSince($0.value.grantedAt) < PhoneVisitPolicy.grantLifetime }
    }
}
