import Foundation

/// How relevant a widget is right now, for Smart Rotate in a widget stack
/// (`WidgetStack`), as iPadOS widgets tell a Smart Stack. A widget says it
/// with `WidgetDescriptor(…, relevance:)`, and the stack turns to the most
/// relevant of its widgets and back to the one the person had once that passes.
///
///     WidgetDescriptor(id: "kitchen.timers", …, relevance: { context in
///         context.services.timers.timers.contains { $0.status == .running } ? .timely() : nil
///     }) { size in … }
///
/// The stack asks inside a view, so a hook that reads `@Observable` models
/// (a timer starting, music stopping) is asked again on its own when they
/// change. A time on the answer (`until`) has the stack ask again then too.
public struct WidgetRelevance: Equatable, Sendable {
    /// How relevant, from 0 (not at all) to 1. Use the steps below, so
    /// widgets from different modules compare fairly.
    public var score: Double
    /// When this answer stops holding. A widget with a score stays relevant
    /// until then even once the hook stops saying so, such as a camera after
    /// the doorbell's banner has closed. With a score of 0 it is when the
    /// widget will have something to say, such as half an hour before an event,
    /// and the stack asks again then. Nil holds for as long as the hook keeps
    /// returning it, such as music while it plays.
    public var until: Date?

    public init(score: Double, until: Date? = nil) {
        self.score = min(max(score, 0), 1)
        self.until = until
    }

    /// True when the widget has something to show now.
    public var isRelevant: Bool { score > 0 }

    /// How long something that happened stays relevant once it is over, such
    /// as a doorbell ring: long enough to answer the door and come back to
    /// see who it was on the stack.
    public static let afterEvent: TimeInterval = 10 * 60

    /// Something to look at or act on now: a doorbell ring, a door left open,
    /// an unlocked lock, a weather alert.
    public static func needsLook(until: Date? = nil) -> WidgetRelevance {
        WidgetRelevance(score: 1, until: until)
    }

    /// Something with a time on it now: a timer running, an event about to
    /// start or under way, rain or snow on the way.
    public static func timely(until: Date? = nil) -> WidgetRelevance {
        WidgetRelevance(score: 0.75, until: until)
    }

    /// Something going on: music playing.
    public static func ongoing(until: Date? = nil) -> WidgetRelevance {
        WidgetRelevance(score: 0.5, until: until)
    }

    /// Nothing now, but ask again at `date`, when it may have something.
    public static func notYet(until date: Date) -> WidgetRelevance {
        WidgetRelevance(score: 0, until: date)
    }
}

/// A widget's relevance hook (`WidgetDescriptor.relevance`): how relevant it
/// is in a context, or nil when it has nothing to say.
public typealias WidgetRelevanceHook = @MainActor (WidgetRelevanceContext) -> WidgetRelevance?

/// What a widget's relevance hook gets: the time to judge, the placed
/// widget's own settings and the app's services, which its view would read
/// from the environment.
@MainActor
public struct WidgetRelevanceContext {
    public var date: Date
    public var settings: WidgetSettings
    public var services: AppServices

    public init(date: Date, settings: WidgetSettings, services: AppServices) {
        self.date = date
        self.settings = settings
        self.services = services
    }
}
