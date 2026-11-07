import Foundation

/// Temporal voting over recent match decisions. One good frame is not enough:
/// a member is confirmed only after winning most of the recent votes, and
/// clearly beating any other member.
struct RecognitionVoter: Equatable, Sendable {
    /// How many recent decisions count.
    var windowSize: Int
    /// Votes the winner needs inside the window.
    var requiredVotes: Int
    /// Decisions older than this are dropped.
    var maxAge: TimeInterval = 4

    private var votes: [Vote] = []

    private struct Vote: Equatable, Sendable {
        let time: Date
        let memberID: UUID?
    }

    init(windowSize: Int, requiredVotes: Int, maxAge: TimeInterval = 4) {
        self.windowSize = windowSize
        self.requiredVotes = requiredVotes
        self.maxAge = maxAge
    }

    /// Adds a decision and returns the confirmed member, if any.
    /// Unknown and spoof decisions take window slots, which delays confirmation.
    mutating func add(_ decision: MatchDecision, at time: Date) -> UUID? {
        votes.append(Vote(time: time, memberID: decision.memberID))
        votes.removeAll { time.timeIntervalSince($0.time) > maxAge }
        if votes.count > windowSize { votes.removeFirst(votes.count - windowSize) }
        return winner
    }

    /// The member currently confirmed by the window, if any.
    var winner: UUID? {
        var counts: [UUID: Int] = [:]
        for vote in votes {
            if let id = vote.memberID { counts[id, default: 0] += 1 }
        }
        let ranked = counts.sorted { $0.value > $1.value }
        guard let best = ranked.first, best.value >= requiredVotes else { return nil }
        let second = ranked.dropFirst().first?.value ?? 0
        // The winner must clearly dominate any competitor.
        return best.value >= second * 2 ? best.key : nil
    }

    mutating func reset() {
        votes.removeAll()
    }

    /// The window for diagnostics: one letter per vote, M for a member, - for unknown.
    var voteSummary: String {
        votes.map { $0.memberID == nil ? "-" : "M" }.joined()
    }
}
