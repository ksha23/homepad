import Foundation
import HomePadCore
import Testing
@testable import HomePadKitchen

/// A clock tests move by hand.
@MainActor
final class TestClock {
    var now = Date(timeIntervalSince1970: 1_800_000_000)
    func advance(_ seconds: TimeInterval) { now = now.addingTimeInterval(seconds) }
}

/// Records alarm calls and can pretend the system alarm was stopped outside the app.
@MainActor
final class RecordingAlarms: TimerAlarmScheduling {
    var scheduled: [UUID: Date] = [:]
    var cancelled: [UUID] = []
    var dismissedOutside: Set<UUID> = []
    var authorization: TimerAlarmAuthorization { .authorized }
    func requestAuthorization() async {}
    func schedule(_ timer: HomeTimer) { scheduled[timer.id] = timer.endDate }
    func cancel(_ id: UUID) { cancelled.append(id); scheduled[id] = nil }
    func wasDismissedOutsideApp(_ id: UUID) -> Bool { dismissedOutside.contains(id) }
}

@MainActor
@Suite struct TimerServiceTests {
    let directory = FileManager.default.temporaryDirectory.appending(path: "kitchen-tests-\(UUID().uuidString)")
    let clock = TestClock()
    let alarms = RecordingAlarms()
    let events = EventBus()

    private var store: TimerStateStore { TimerStateStore(fileURL: directory.appending(path: "timers.json")) }

    private func makeService() -> KitchenTimerService {
        let clock = clock
        return KitchenTimerService(store: store, events: events, alarms: alarms, surfaces: NoTimerSurfaces(), clock: { clock.now })
    }

    private var finishedEvents: [String] {
        events.recent.compactMap { _, event in
            if case .timerFinished(_, let label) = event { return label }
            return nil
        }
    }

    @Test func startsNamedTimersWithDefaultLabels() {
        let service = makeService()
        let pasta = service.start(duration: 600, label: "Pasta")
        let unnamed = service.start(duration: 390, label: "  ")
        #expect(service.timers.count == 2)
        #expect(pasta.endDate == clock.now.addingTimeInterval(600))
        #expect(unnamed.label == "6 min 30 sec")
        #expect(alarms.scheduled[pasta.id] == clock.now.addingTimeInterval(600))
    }

    @Test func pauseResumeKeepsRemainingTime() throws {
        let service = makeService()
        let timer = service.start(duration: 300, label: "Tea")
        clock.advance(100)
        service.pause(timer.id)
        var paused = try #require(service.timers.first)
        #expect(paused.status == .paused)
        #expect(paused.remaining(at: clock.now) == 200)
        #expect(alarms.cancelled.contains(timer.id))

        clock.advance(1000) // paused time does not count
        #expect(paused.remaining(at: clock.now) == 200)
        service.resume(timer.id)
        paused = try #require(service.timers.first)
        #expect(paused.status == .running)
        #expect(paused.endDate == clock.now.addingTimeInterval(200))
        #expect(alarms.scheduled[timer.id] == clock.now.addingTimeInterval(200))
    }

    @Test func addMinuteToRunningPausedAndFinished() throws {
        let service = makeService()
        let running = service.start(duration: 60, label: "A")
        service.add(60, to: running.id)
        #expect(service.timers[0].endDate == clock.now.addingTimeInterval(120))
        #expect(service.timers[0].duration == 120)

        let paused = service.start(duration: 60, label: "B")
        service.pause(paused.id)
        service.add(60, to: paused.id)
        #expect(service.timers[1].remainingWhenPaused == 120)

        clock.advance(121)
        service.refresh()
        #expect(service.timers[0].status == .finished)
        service.add(60, to: running.id)
        #expect(service.timers[0].status == .running)
        #expect(service.timers[0].duration == 60)
        #expect(service.timers[0].remaining(at: clock.now) == 60)
    }

    @Test func finishingPostsEventAndCancelsSystemAlarm() {
        let service = makeService()
        let eggs = service.start(duration: 390, label: "Eggs")
        service.start(duration: 900, label: "Rice")
        clock.advance(389)
        service.refresh()
        #expect(finishedEvents.isEmpty)
        clock.advance(1)
        service.refresh()
        #expect(finishedEvents == ["Eggs"])
        #expect(service.timers.first { $0.id == eggs.id }?.status == .finished)
        #expect(alarms.cancelled.contains(eggs.id))
        service.refresh()
        #expect(finishedEvents == ["Eggs"], "announced once")
    }

    @Test func timerStoppedOnLockScreenDoesNotRingAgain() {
        let service = makeService()
        let timer = service.start(duration: 60, label: "Steep")
        alarms.dismissedOutside.insert(timer.id)
        clock.advance(120)
        service.refresh()
        #expect(service.timers.isEmpty)
        #expect(finishedEvents.isEmpty)
    }

    @Test func cancelRemovesTimerAndAlarm() {
        let service = makeService()
        let a = service.start(duration: 10, label: "A")
        service.start(duration: 10, label: "B")
        service.cancel(a.id)
        #expect(service.timers.map(\.label) == ["B"])
        #expect(alarms.cancelled == [a.id])
        #expect(alarms.scheduled[a.id] == nil)
    }

    // MARK: Persistence

    @Test func stateSurvivesRelaunch() throws {
        let first = makeService()
        let running = first.start(duration: 600, label: "Roast")
        let paused = first.start(duration: 300, label: "Dough")
        clock.advance(60)
        first.pause(paused.id)

        clock.advance(120) // HomePad was closed for two minutes
        let second = makeService()
        #expect(second.timers.map(\.id) == [running.id, paused.id])
        #expect(second.timers[0].remaining(at: clock.now) == 420)
        #expect(second.timers[1].status == .paused)
        #expect(second.timers[1].remaining(at: clock.now) == 240)
        #expect(second.timers[1].label == "Dough")
    }

    @Test func timerThatEndedWhileClosedRingsOnLaunch() {
        let first = makeService()
        first.start(duration: 60, label: "Kettle")
        clock.advance(90)
        let second = makeService()
        #expect(second.timers.first?.status == .finished)
        #expect(finishedEvents == ["Kettle"])
    }

    @Test func longAgoTimersAreDroppedOnLaunch() {
        let first = makeService()
        first.start(duration: 60, label: "Old")
        let paused = first.start(duration: 60, label: "Paused")
        first.pause(paused.id)
        clock.advance(KitchenTimerService.staleAfter + 120)
        let second = makeService()
        #expect(second.timers.map(\.label) == ["Paused"])
        #expect(finishedEvents.isEmpty)
    }

    @Test func storeRoundTripsAndToleratesMissingFile() {
        #expect(store.load().isEmpty)
        let timers = [HomeTimer(label: "X", duration: 5, status: .paused, remainingWhenPaused: 3)]
        store.save(timers)
        #expect(store.load() == timers)
    }

    // MARK: Live Activity state

    @Test func contentStateOrdersSoonestFirstAndFinishedLast() {
        let now = clock.now
        let timers = [
            HomeTimer(label: "Later", duration: 900, status: .running, endDate: now.addingTimeInterval(900)),
            HomeTimer(label: "Done", duration: 60, status: .finished, endDate: now.addingTimeInterval(-5)),
            HomeTimer(label: "Soon", duration: 120, status: .running, endDate: now.addingTimeInterval(30)),
            HomeTimer(label: "Paused", duration: 600, status: .paused, remainingWhenPaused: 300),
        ]
        let state = TimerSurfaceSync.contentState(for: timers, now: now)
        #expect(state.timers.map(\.label) == ["Soon", "Paused", "Later", "Done"])
        #expect(state.featured?.label == "Soon")
        #expect(state.timers[1].remaining(at: now) == 300)
    }

    // MARK: Formatting

    @Test(arguments: [(287.0, "04:47"), (0.2, "00:01"), (3725, "1:02:05"), (900, "15:00")])
    func countdownText(_ seconds: TimeInterval, _ expected: String) {
        #expect(TimerFormat.countdown(seconds) == expected)
    }

    @Test func totalsAndLabels() {
        #expect(TimerFormat.total(900) == "15 MIN")
        #expect(TimerFormat.spoken(5400) == "1 hr 30 min")
        #expect(TimerFormat.spoken(45) == "45 sec")
    }

    @Test func chimeAudioIsAValidLoopingWAV() {
        for sound in ChimeSound.allCases {
            let data = ChimeSynthesizer.wav(for: sound)
            #expect(data.prefix(4) == Data("RIFF".utf8))
            #expect(data.count == 44 + Int(sound.pattern.loopLength * ChimeSynthesizer.sampleRate) * 2)
        }
    }
}
