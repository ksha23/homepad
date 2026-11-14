import Foundation

/// Depth identity's votes on one look, while depth decides who is in view
/// in the dark (`FaceRecognitionService.noteDepthScore`).
///
/// A signature votes for the member it came under the calibrated limit of
/// (`DepthCalibration`), when every other member is at least `marginFactor`
/// times farther, or for no one. `requiredDepthVotes` of the last
/// `depthWindow` votes for one member name them.
struct DepthVoter {
    let policy: DepthTemplatePolicy
    /// Newest last: the member voted for, or nil.
    private(set) var votes: [UUID?] = []

    init(policy: DepthTemplatePolicy) {
        self.policy = policy
    }

    /// One signature's vote and why, and the member it names, if any.
    struct Outcome {
        var vote: UUID?
        /// "Kyle 0.85 mm, under the 1.50 mm limit", for the trace.
        var reason: String
        var winner: UUID?
        /// Votes for the winner.
        var winnerVotes = 0
    }

    /// Votes on `score`, with each member's limit in `limits`. `name` is for the reason only.
    mutating func vote(on score: DepthIdentityScore, limits: [UUID: Double], name: (UUID) -> String) -> Outcome {
        var outcome = Outcome(vote: nil, reason: "no face to compare with")
        if let best = score.other, let member = score.otherMember {
            let distance = name(member) + " " + Self.millimeters(best)
            if let limit = limits[member] {
                if best > limit {
                    outcome.reason = distance + ", over the " + Self.millimeters(limit) + " limit"
                } else if (score.runnerUp ?? .infinity) < best * policy.marginFactor {
                    outcome.reason = distance + ", too close to someone else"
                } else {
                    outcome.vote = member
                    outcome.reason = distance + ", under the " + Self.millimeters(limit) + " limit"
                }
            } else {
                outcome.reason = distance + ", no limit yet"
            }
        }
        votes.append(outcome.vote)
        if votes.count > policy.depthWindow { votes.removeFirst(votes.count - policy.depthWindow) }
        let counts = Dictionary(votes.compactMap { $0 }.map { ($0, 1) }, uniquingKeysWith: +)
        if let (winner, count) = counts.max(by: { $0.value < $1.value }), count >= policy.requiredDepthVotes {
            outcome.winner = winner
            outcome.winnerVotes = count
        }
        return outcome
    }

    mutating func reset() {
        votes.removeAll()
    }

    /// "K K - K, 3 of 4 needed", for the debug view.
    func describe(name: (UUID) -> String) -> String {
        let marks = votes.map { vote in vote.map { String(name($0).prefix(1)) } ?? "-" }
        let shown = marks.isEmpty ? "none yet" : marks.joined(separator: " ")
        return shown + ", \(policy.requiredDepthVotes) of \(policy.depthWindow) needed"
    }

    private static func millimeters(_ value: Double) -> String {
        String(format: "%.2f mm", value)
    }
}
