import Foundation

/// On a HomePad: the approval requests it sent, and the checks every answer
/// must pass. A pure value with an injected clock, so it is unit tested.
///
/// An answer counts only when it
/// 1. answers a request this HomePad sent and has not settled (no replays),
/// 2. arrives before the request's lifetime ends on this HomePad's clock,
/// 3. comes from a device linked to the request's member, over its session,
/// 4. and, to approve, carries that device's signature over the request.
///
/// A denial from the right device ends the request without a signature. An
/// answer that fails a check is dropped and leaves the request open, so a
/// stray or forged answer cannot end someone's request.
struct ApprovalLedger {
    enum Rejection: Equatable {
        /// No request with this ID was sent.
        case unknownRequest
        /// The request was already answered, withdrawn or expired.
        case replayed
        /// The answer came after the request ran out.
        case expired
        /// The sender is not linked to the request's member.
        case wrongDevice
        /// An approval without a valid signature from the linked device.
        case badSignature
    }

    enum Verdict: Equatable {
        case approved(ApprovalRequest)
        case denied(ApprovalRequest)
        case rejected(Rejection)
    }

    private struct Open {
        let request: ApprovalRequest
        let deadline: Date
    }

    private var open: [UUID: Open] = [:]
    /// Requests no longer open, by when they closed, so a second answer reads
    /// as a replay. Kept for ten minutes.
    private var settled: [UUID: Date] = [:]
    private static let settledMemory: TimeInterval = 600

    /// Opens a request. Its deadline counts from `now`.
    mutating func issue(_ request: ApprovalRequest, now: Date) {
        settled = settled.filter { now.timeIntervalSince($0.value) < Self.settledMemory }
        open[request.id] = Open(request: request, deadline: now.addingTimeInterval(request.lifetime))
    }

    func isOpen(_ id: UUID) -> Bool { open[id] != nil }

    /// Checks one answer from `deviceID` against `devices`, the HomePad's links.
    mutating func verify(_ response: ApprovalResponse, from deviceID: String, devices: [LinkedDevice], now: Date) -> Verdict {
        if settled[response.requestID] != nil { return .rejected(.replayed) }
        guard let entry = open[response.requestID] else { return .rejected(.unknownRequest) }
        guard now < entry.deadline else {
            settle(response.requestID, now: now)
            return .rejected(.expired)
        }
        let request = entry.request
        guard let device = devices.first(where: { $0.id == deviceID && $0.memberID == request.memberID && $0.canApprove }) else {
            return .rejected(.wrongDevice)
        }
        switch response.decision {
        case .deny:
            settle(request.id, now: now)
            return .denied(request)
        case .approve:
            guard let signature = response.signature, device.signed(request.signedBytes(for: .approve), with: signature) else {
                return .rejected(.badSignature)
            }
            settle(request.id, now: now)
            return .approved(request)
        }
    }

    /// Closes a request nobody answered: cancelled, unreachable or run out.
    mutating func withdraw(_ id: UUID, now: Date) {
        guard open[id] != nil else { return }
        settle(id, now: now)
    }

    private mutating func settle(_ id: UUID, now: Date) {
        open[id] = nil
        settled[id] = now
    }
}
