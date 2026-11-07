import Foundation
import HomePadCore
import SwiftUI
import Testing
@testable import HomePadShell

@MainActor
@Suite struct TopPillsTests {
    private let now = Date(timeIntervalSinceReferenceDate: 800_000_000)

    private func running(_ label: String, endsIn seconds: TimeInterval) -> HomeTimer {
        HomeTimer(label: label, duration: 900, status: .running, endDate: now.addingTimeInterval(seconds))
    }

    private func paused(_ label: String, left seconds: TimeInterval) -> HomeTimer {
        HomeTimer(label: label, duration: 900, status: .paused, remainingWhenPaused: seconds)
    }

    @Test func theSoonestRunningTimerComesFirst() {
        let timers = [running("Pasta", endsIn: 600), paused("Bread", left: 30), running("Eggs", endsIn: 200)]
        let ordered = TopPillsContent.ordered(timers, at: now)
        #expect(ordered.map(\.label) == ["Eggs", "Pasta", "Bread"])
    }

    /// A finished timer rings full screen, so the pill leaves it out.
    @Test func finishedTimersAreLeftOut() {
        let done = HomeTimer(label: "Tea", duration: 60, status: .finished)
        let ordered = TopPillsContent.ordered([done, paused("Bread", left: 30)], at: now)
        #expect(ordered.map(\.label) == ["Bread"])
    }

    @Test func pausedTimersShowWhenNoneRun() {
        let ordered = TopPillsContent.ordered([paused("Bread", left: 900), paused("Rice", left: 300)], at: now)
        #expect(ordered.first?.label == "Rice")
    }

    @Test func theContentCountsTheOtherTimers() {
        let services = AppServices(settings: SettingsStore(defaults: UserDefaults(suiteName: "homepad.shell.pills.\(UUID().uuidString)")!))
        let timers = InMemoryTimerService()
        services.timers = timers
        timers.start(duration: 600, label: "Pasta")
        timers.start(duration: 120, label: "Eggs")
        let content = TopPillsContent(services: services)
        #expect(content.timer?.label == "Eggs")
        #expect(content.otherTimers == 1)
        #expect(TopPillsContent(services: services, showsTimer: false).isEmpty)
    }

    /// Beside a timer the Now Playing pill steps down a size, so the pair
    /// keeps to the zone headers leave free.
    @Test func nowPlayingStepsDownBesideATimer() {
        #expect(NowPlayingPill.Content.content(isCompact: false, besideTimer: false) == .titles)
        #expect(NowPlayingPill.Content.content(isCompact: false, besideTimer: true) == .bars)
        #expect(NowPlayingPill.Content.content(isCompact: true, besideTimer: false) == .bars)
        #expect(NowPlayingPill.Content.content(isCompact: true, besideTimer: true) == .cover)
    }

    @Test func countdownsRoundUpLikeTheDynamicIsland() {
        #expect(TimerPill.countdown(286.2) == "4:47")
        #expect(TimerPill.countdown(887) == "14:47")
        #expect(TimerPill.countdown(3887) == "1:04:47")
        #expect(TimerPill.countdown(0.3) == "0:01")
    }

    @Test func theSpokenLabelNamesTheTimerAndTheOthers() {
        let label = TimerPill.spokenLabel(for: running("Pasta", endsIn: 600), remaining: 125, others: 2)
        #expect(label.hasPrefix("Pasta, "))
        #expect(label.hasSuffix("left, and 2 more timers"))
    }

    /// The countdown redraws on each whole second before the end, once a
    /// second at most, and stops at the end.
    @Test func theScheduleTicksOnTheSecondsBeforeTheEnd() {
        let end = now.addingTimeInterval(3.4)
        let entries = Array(CountdownSchedule(end: end).entries(from: now, mode: .normal))
        #expect(entries.map { $0.timeIntervalSince(now) } .map { ($0 * 10).rounded() / 10 } == [0, 0.4, 1.4, 2.4, 3.4])
    }
}
