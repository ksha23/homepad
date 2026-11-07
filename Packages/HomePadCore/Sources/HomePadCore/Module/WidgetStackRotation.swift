import Foundation
import Observation

/// Smart Rotate's rules: which widget a stack shows. Pure, so tests drive it
/// with plain values. `WidgetStackMemory` keeps what they need between draws.
///
/// - The stack rests on the person's widget: the one they last flipped to,
///   or its first.
/// - It turns to the most relevant widget (`WidgetRelevance`) when that is
///   more relevant than the person's, and back once it no longer is.
/// - A widget the person flipped to by hand stays for `manualHold` before
///   Smart Rotate turns the stack again, as on iPadOS.
/// - With Smart Rotate off it shows the person's widget only.
public enum WidgetStackRotation {
    /// How long a widget the person flipped to stays before Smart Rotate may
    /// turn the stack again: long enough to read it and walk off, short
    /// enough that the stack is back at work for the next person walking past.
    public static let manualHold: TimeInterval = 10 * 60

    /// What a stack shows, and when to look again.
    public struct Decision: Equatable, Sendable {
        /// The member on top.
        public var memberID: String
        /// When time alone may change the decision: a relevance running out or
        /// starting, or a hold ending. Nil when only a change in what the
        /// widgets read can change it.
        public var nextCheck: Date?

        public init(memberID: String, nextCheck: Date?) {
            self.memberID = memberID
            self.nextCheck = nextCheck
        }
    }

    /// The widget the stack shows.
    ///
    /// - Parameters:
    ///   - memberIDs: The stack's widgets in order, only those that can show now.
    ///   - relevance: How relevant each is now (`standing(live:held:now:)`).
    ///   - chosenID: The widget the person last flipped to, if any.
    ///   - chosenAt: When they did.
    /// - Returns: Nil for a stack with nothing to show.
    public static func decide(
        memberIDs: [String], relevance: [String: WidgetRelevance], chosenID: String?, chosenAt: Date?,
        smartRotate: Bool, now: Date
    ) -> Decision? {
        guard let first = memberIDs.first else { return nil }
        let home = chosenID.flatMap { memberIDs.contains($0) ? $0 : nil } ?? first
        guard smartRotate else { return Decision(memberID: home, nextCheck: nil) }
        if let chosenAt, chosenID == home {
            let holdEnds = chosenAt.addingTimeInterval(manualHold)
            if holdEnds > now { return Decision(memberID: home, nextCheck: holdEnds) }
        }
        let nextCheck = memberIDs.compactMap { relevance[$0]?.until }.filter { $0 > now }.min()
        // The first of equally relevant widgets, so the same answers always show the same one.
        var best: (id: String, score: Double)?
        for id in memberIDs {
            let score = relevance[id]?.score ?? 0
            if score > (best?.score ?? 0) { best = (id, score) }
        }
        let homeScore = relevance[home]?.score ?? 0
        guard let best, best.score > homeScore else { return Decision(memberID: home, nextCheck: nextCheck) }
        return Decision(memberID: best.id, nextCheck: nextCheck)
    }

    /// The relevance that counts at `now`: what each widget says now, or what
    /// it said earlier with a time on it that has not passed (`held`).
    public static func standing(
        live: [String: WidgetRelevance], held: [String: WidgetRelevance], now: Date
    ) -> [String: WidgetRelevance] {
        var standing = held.filter { $0.value.until.map { $0 > now } ?? false }
        for (id, relevance) in live { standing[id] = relevance }
        return standing
    }

    /// What to keep for later: each relevant answer with a time on it, so it
    /// stays when its widget stops saying it (a doorbell's banner closing).
    /// A new answer replaces the one kept, and kept ones drop once their time passes.
    public static func holding(
        live: [String: WidgetRelevance], held: [String: WidgetRelevance], now: Date
    ) -> [String: WidgetRelevance] {
        var kept = held.filter { $0.value.until.map { $0 > now } ?? false }
        for (id, relevance) in live {
            if relevance.isRelevant, let until = relevance.until, until > now {
                kept[id] = relevance
            } else {
                kept[id] = nil
            }
        }
        return kept
    }
}

/// What each widget stack remembers while HomePad runs, by the stack's ID:
/// the widget the person flipped to and when, the relevance its widgets
/// reported with a time on it, and the widget on top now. The same stack
/// drawn in two places (a face on the wall and in its editor) shares it.
/// It is not saved: after a restart each stack rests on its first widget.
@MainActor
@Observable
public final class WidgetStackMemory {
    /// A widget the person flipped to by hand.
    public struct Choice: Equatable, Sendable {
        public var memberID: String
        public var date: Date
    }

    public private(set) var choices: [String: Choice] = [:]
    /// Relevance reported with a time on it, by stack and then by member (`WidgetStackRotation.holding`).
    public private(set) var held: [String: [String: WidgetRelevance]] = [:]
    /// The widget on top of each stack as it last came to rest. Taps and the
    /// Home Screen's label read it. Kept apart, so the stacks that write it
    /// do not draw again because of it.
    public private(set) var shown: [String: String] = [:]

    public init() {}

    /// The person flipped to a widget.
    public func choose(_ memberID: String, in stackID: String, at date: Date = Date()) {
        choices[stackID] = Choice(memberID: memberID, date: date)
    }

    public func keep(_ relevance: [String: WidgetRelevance], in stackID: String) {
        guard held[stackID, default: [:]] != relevance else { return }
        held[stackID] = relevance.isEmpty ? nil : relevance
    }

    /// The widget on top now.
    public func show(_ memberID: String, in stackID: String) {
        guard shown[stackID] != memberID else { return }
        shown[stackID] = memberID
    }

    public func shownMemberID(in stackID: String) -> String? {
        shown[stackID]
    }
}
