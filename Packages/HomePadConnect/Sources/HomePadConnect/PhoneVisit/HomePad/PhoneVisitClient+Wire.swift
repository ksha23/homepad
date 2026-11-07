import Foundation
import HomePadCore

// The HomePad's side of the visit handshake, and the plumbing every kind's
// requests share: one session, answers matched by request ID.
extension PhoneVisitClient {
    func registerHandlers() {
        link.on(.visitChallenge) { [weak self] message, peer in
            guard let challenge = try? message.content(PhoneVisitChallenge.self) else { return }
            self?.receive(challenge, from: peer)
        }
        link.on(.visitOpened) { [weak self] message, peer in
            guard let opened = try? message.content(PhoneVisitOpened.self) else { return }
            self?.receive(opened, from: peer)
        }
        link.on(.visitRefused) { [weak self] message, peer in
            guard let refused = try? message.content(PhoneVisitRefused.self) else { return }
            self?.receive(refused, from: peer)
        }
        link.onConnect { [weak self] peer in self?.peerConnected(peer) }
        link.onDisconnect { [weak self] peerID in self?.peerDisconnected(peerID) }
    }

    // MARK: Opening

    /// Opens the phone for this visit: on the session already open, or after
    /// waking the phone over Bluetooth. False when the phone does not answer
    /// in time or says no.
    func open(_ visit: PhoneVisit) async -> Bool {
        if let granted = visit.grantedSession, currentSession(visit.deviceID) == granted { return true }
        visit.grantedSession = nil
        guard isCurrent(visit) else { return false }
        let waiterID = UUID()
        let timeout = openTimeout
        return await withCheckedContinuation { continuation in
            let isFirst = visit.openWaiters.isEmpty
            visit.openWaiters[waiterID] = continuation
            Task {
                try? await Task.sleep(for: .seconds(timeout))
                visit.openWaiters.removeValue(forKey: waiterID)?.resume(returning: false)
            }
            if isFirst { beginOpening(visit) }
        }
    }

    /// Says hello on the open session and wakes the phone only if it does
    /// not answer, since a wake makes a phone in the background start its
    /// link over. With no session it wakes the phone at once, and says hello
    /// when the phone connects.
    private func beginOpening(_ visit: PhoneVisit) {
        guard currentSession(visit.deviceID) != nil else { return wake(visit) }
        sendHello(visit)
        Task {
            try? await Task.sleep(for: .seconds(3))
            guard isCurrent(visit), !visit.openWaiters.isEmpty else { return }
            wake(visit)
        }
    }

    /// Wakes the phone over Bluetooth, at most every 15 seconds.
    private func wake(_ visit: PhoneVisit) {
        if let last = visit.lastWake, now().timeIntervalSince(last) < 15 { return }
        visit.lastWake = now()
        if waker?.wake(visit.wakeTag) != true {
            log.info("\(visit.deviceName, privacy: .public) is not connected over Bluetooth")
        }
    }

    func sendHello(_ visit: PhoneVisit) {
        let hello = PhoneVisitHello(memberID: visit.memberID, kinds: PhoneDataKind.names(visit.kinds))
        visit.helloID = hello.requestID
        guard let message = try? link.message(.visitHello, hello) else { return }
        let deviceID = visit.deviceID
        Task { try? await transmit(message, deviceID) }
    }

    /// Signs the phone's nonce, only during a visit, so only for the member
    /// recognized here right now.
    func receive(_ challenge: PhoneVisitChallenge, from peer: PeerDevice) {
        guard let visit, peer.id == visit.deviceID, challenge.requestID == visit.helloID,
              let session = peer.sessionID, let key = approver.homePadKey else { return }
        let bytes = PhoneVisitOpen.signedBytes(requestID: challenge.requestID, nonce: challenge.nonce, memberID: visit.memberID,
                                               homePadID: link.identity.deviceID, phoneID: peer.id)
        guard let signature = try? key.sign(bytes),
              let message = try? link.message(.visitOpen, PhoneVisitOpen(requestID: challenge.requestID, signature: signature)) else { return }
        try? transmitOnSession(message, peer.id, session)
    }

    func receive(_ opened: PhoneVisitOpened, from peer: PeerDevice) {
        guard let visit, peer.id == visit.deviceID, opened.requestID == visit.helloID, let session = peer.sessionID else { return }
        visit.helloID = nil
        visit.grantedSession = session
        visit.grantedKinds = opened.grantedKinds.intersection(visit.kinds)
        visit.hasAnswered = true
        let waiters = visit.openWaiters
        visit.openWaiters = [:]
        waiters.values.forEach { $0.resume(returning: true) }
        publish(visit)
    }

    func receive(_ refused: PhoneVisitRefused, from peer: PeerDevice) {
        guard let visit, peer.id == visit.deviceID, refused.requestID == visit.helloID else { return }
        visit.helloID = nil
        log.info("\(visit.deviceName, privacy: .public) did not open: \(refused.reason.rawValue, privacy: .public)")
        let waiters = visit.openWaiters
        visit.openWaiters = [:]
        waiters.values.forEach { $0.resume(returning: false) }
    }

    /// Tells the phone the HomePad needs nothing more for now, so it can stop.
    func closeSession(of visit: PhoneVisit) {
        guard let session = visit.grantedSession, let close = try? link.message(.visitClose, PhoneVisitClose()) else { return }
        visit.grantedSession = nil
        try? transmitOnSession(close, visit.deviceID, session)
    }

    /// Closes the session once the first fetch is done and no answer is
    /// awaited, so a change on its way to the phone is never cut off.
    func closeIfIdle(_ visit: PhoneVisit) {
        guard isCurrent(visit), visit.hasFetched, visit.replyWaiters.isEmpty else { return }
        closeSession(of: visit)
    }

    // MARK: Requests

    /// Asks the phone and waits for its answer, on the session it opened.
    /// Nil when the phone cannot be opened, the send fails, or no answer comes in time.
    func request<Content: Encodable>(_ type: PeerMessageType, _ content: Content, id: UUID, in visit: PhoneVisit,
                                     timeout: TimeInterval? = nil) async -> PeerMessage? {
        guard await open(visit), isCurrent(visit), let session = visit.grantedSession,
              let message = try? link.message(type, content) else { return nil }
        let timeout = timeout ?? replyTimeout
        return await withCheckedContinuation { continuation in
            visit.replyWaiters[id] = continuation
            do {
                try transmitOnSession(message, visit.deviceID, session)
            } catch {
                visit.replyWaiters.removeValue(forKey: id)?.resume(returning: nil)
                return
            }
            Task {
                try? await Task.sleep(for: .seconds(timeout))
                visit.replyWaiters.removeValue(forKey: id)?.resume(returning: nil)
            }
        }
    }

    /// Hands an answer to whoever waits for it, if it came on the granted session.
    func deliver(_ message: PeerMessage, answering requestID: UUID, from peer: PeerDevice) {
        guard let visit = grantedVisit(for: peer) else { return }
        visit.replyWaiters.removeValue(forKey: requestID)?.resume(returning: message)
    }

    /// Sends without waiting, on the session the phone opened. For answers
    /// that come in many messages, such as photos.
    func sendOnGrantedSession(_ message: PeerMessage, in visit: PhoneVisit) throws {
        guard isCurrent(visit), let session = visit.grantedSession else { throw PeerLinkError.notConnected }
        try transmitOnSession(message, visit.deviceID, session)
    }

    /// The visit `peer` may answer for: its phone, on the session it opened.
    func grantedVisit(for peer: PeerDevice) -> PhoneVisit? {
        guard let visit, peer.id == visit.deviceID, peer.sessionID != nil, peer.sessionID == visit.grantedSession else { return nil }
        return visit
    }

    // MARK: Sessions

    /// The phone joined the peer link: say hello if the visit is waiting for
    /// it, start the visit's first fetch over if it ran out before, or let
    /// the parts send what waited for the phone.
    func peerConnected(_ peer: PeerDevice) {
        guard let visit, peer.id == visit.deviceID else { return }
        if !visit.openWaiters.isEmpty {
            sendHello(visit)
        } else if !visit.hasAnswered {
            Task { await run(visit) }
        } else {
            parts(for: visit.kinds).forEach { $0.phoneConnected(visit) }
        }
        publish(visit)
    }

    func peerDisconnected(_ peerID: String) {
        guard let visit, peerID == visit.deviceID else { return }
        visit.grantedSession = nil
        publish(visit)
    }
}
