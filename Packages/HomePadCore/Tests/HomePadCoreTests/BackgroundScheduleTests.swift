import Foundation
import Testing
@testable import HomePadCore

/// When background tasks run: their time, requests, retries, what blocks them,
/// which one goes first, and the runner that starts, stops and records them.
@Suite struct BackgroundScheduleTests {
    let t0 = Date(timeIntervalSinceReferenceDate: 800_000_000)

    private func idle(_ display: DisplayCondition = .ambient, onPower: Bool = true) -> BackgroundEnvironment {
        BackgroundEnvironment(isForeground: true, display: display, isOnPower: onPower, isInteracting: false, isOverheating: false)
    }

    // MARK: Time

    @Test func aTaskThatNeverRanIsDueAtOnce() {
        #expect(BackgroundSchedule.isDue(BackgroundTaskRecord(), interval: 3600, retryInterval: nil, now: t0))
    }

    @Test func aDoneTaskWaitsItsInterval() {
        let record = BackgroundTaskRecord(lastRun: t0, lastFinished: t0, outcome: .done("ok"))
        #expect(BackgroundSchedule.nextRun(record, interval: 3600, retryInterval: nil, now: t0) == t0 + 3600)
        #expect(!BackgroundSchedule.isDue(record, interval: 3600, retryInterval: nil, now: t0 + 3599))
        #expect(BackgroundSchedule.isDue(record, interval: 3600, retryInterval: nil, now: t0 + 3600))
    }

    @Test func aFailedTaskRetriesSooner() {
        let record = BackgroundTaskRecord(lastRun: t0, lastFinished: t0, outcome: .failed("offline"))
        #expect(BackgroundSchedule.nextRun(record, interval: 1800, retryInterval: 300, now: t0) == t0 + 300)
        // A retry never waits longer than the interval itself.
        #expect(BackgroundSchedule.nextRun(record, interval: 60, retryInterval: 300, now: t0) == t0 + 60)
    }

    @Test func aRequestOrAStoppedRunMakesItDueNow() {
        let requested = BackgroundTaskRecord(lastRun: t0, outcome: .done("ok"), request: "Library changed")
        #expect(BackgroundSchedule.isDue(requested, interval: 3600, retryInterval: nil, now: t0 + 1))
        let stopped = BackgroundTaskRecord(lastRun: t0, outcome: .stopped("Someone used the screen"))
        #expect(BackgroundSchedule.isDue(stopped, interval: 3600, retryInterval: nil, now: t0 + 1))
    }

    // MARK: Blockers

    @Test func nothingStartsDuringAZoomATouchOrHeat() {
        var environment = idle()
        environment.isInteracting = true
        #expect(BackgroundSchedule.blocker([], in: environment) == .interacting)
        environment.isInteracting = false
        environment.isOverheating = true
        #expect(BackgroundSchedule.blocker([], in: environment) == .overheating)
    }

    @Test func eachConditionWaitsForItsOwnState() {
        #expect(BackgroundSchedule.blocker(.displayIdle, in: idle(.active)) == .displayInUse)
        #expect(BackgroundSchedule.blocker(.displayIdle, in: idle(.dimmed)) == nil)
        #expect(BackgroundSchedule.blocker(.displayIdle, in: idle(.night)) == nil)
        #expect(BackgroundSchedule.blocker(.displayAsleep, in: idle(.ambient)) == .displayAwake)
        #expect(BackgroundSchedule.blocker(.displayAsleep, in: idle(.sleeping)) == nil)
        #expect(BackgroundSchedule.blocker(.onPower, in: idle(onPower: false)) == .onBattery)
        #expect(BackgroundSchedule.blocker([], in: idle(.active)) == nil)
    }

    @Test func inTheBackgroundOnlyPowerCounts() {
        let away = BackgroundEnvironment.systemLaunch(isOnPower: false)
        #expect(BackgroundSchedule.blocker([.displayIdle, .displayAsleep], in: away) == nil)
        #expect(BackgroundSchedule.blocker(.onPower, in: away) == .onBattery)
    }

    @Test func theMostOverdueUnblockedTaskGoesFirst() {
        let next = BackgroundSchedule.nextTask([
            (id: "weather", nextRun: t0 - 60, isBlocked: false),
            (id: "photos", nextRun: t0 - 600, isBlocked: true),
            (id: "music", nextRun: t0 - 300, isBlocked: false),
            (id: "calendar", nextRun: t0 + 60, isBlocked: false),
        ], now: t0)
        #expect(next == "music")
        #expect(BackgroundSchedule.nextTask([(id: "calendar", nextRun: t0 + 1, isBlocked: false)], now: t0) == nil)
    }

    // MARK: The runner

    @MainActor @Test func nothingRunsUntilAHostStartsIt() async {
        var runs = 0
        let work = BackgroundWork(recordsURL: nil, clock: { self.t0 })
        work.register(BackgroundTaskDescriptor(id: "a", title: "A", summary: "", interval: { 60 }) { _ in
            runs += 1
            return .done("ok")
        })
        work.update(idle())
        await Task.yield()
        #expect(runs == 0)
        work.start()
        work.update(idle())
        await waitUntilIdle(work)
        #expect(runs == 1)
        #expect(work.record(for: "a").outcome == .done("ok"))
        #expect(work.nextRun(for: "a") == t0 + 60)
    }

    @MainActor @Test func preparesOnceWhenStarted() {
        var prepared = 0
        let work = BackgroundWork(recordsURL: nil)
        work.register(BackgroundTaskDescriptor(id: "a", title: "A", summary: "", interval: { 60 }, prepare: { prepared += 1 }) { _ in .done("") })
        #expect(prepared == 0)
        work.start()
        work.start()
        #expect(prepared == 1)
    }

    @MainActor @Test func anIdleTaskStopsWhenSomeoneUsesTheScreenAndStaysDue() async {
        let work = BackgroundWork(recordsURL: nil, clock: { self.t0 })
        let reachedCheckpoint = Signal()
        work.register(BackgroundTaskDescriptor(id: "a", title: "A", summary: "", interval: { 3600 }, conditions: .displayIdle) { context in
            await reachedCheckpoint.wait()
            return await context.checkpoint() ? .done("finished") : .stopped("Someone used the screen")
        })
        work.start()
        work.update(idle(.ambient))
        #expect(work.runningID == "a")
        work.update(idle(.active))
        reachedCheckpoint.fire()
        await waitUntilIdle(work)
        #expect(work.record(for: "a").outcome == .stopped("Someone used the screen"))
        #expect(work.blocker(for: "a") == .displayInUse)
        #expect(BackgroundSchedule.isDue(work.record(for: "a"), interval: 3600, retryInterval: nil, now: t0))
    }

    @MainActor @Test func aCheckpointWaitsOutAZoomThenCarriesOn() async {
        let work = BackgroundWork(recordsURL: nil, clock: { self.t0 })
        let reachedCheckpoint = Signal()
        work.register(BackgroundTaskDescriptor(id: "a", title: "A", summary: "", interval: { 3600 }) { context in
            await reachedCheckpoint.wait()
            return await context.checkpoint() ? .done("finished") : .stopped("stopped")
        })
        work.start()
        work.update(idle())
        var zooming = idle()
        zooming.isInteracting = true
        work.update(zooming)
        reachedCheckpoint.fire()
        for _ in 0..<5 { await Task.yield() }
        #expect(work.runningID == "a")
        work.update(idle())
        await waitUntilIdle(work)
        #expect(work.record(for: "a").outcome == .done("finished"))
    }

    @MainActor @Test func runNowSkipsTimeAndConditionsAndARequestComesNext() async {
        let work = BackgroundWork(recordsURL: nil, clock: { self.t0 })
        var triggers: [BackgroundTrigger] = []
        work.register(BackgroundTaskDescriptor(id: "a", title: "A", summary: "", interval: { 3600 }, conditions: .displayAsleep) { context in
            triggers.append(context.trigger)
            return await context.checkpoint() ? .done("ok") : .stopped("awake")
        })
        work.start()
        work.update(idle(.active))
        #expect(work.runningID == nil)
        work.runNow("a")
        await waitUntilIdle(work)
        #expect(work.record(for: "a").outcome == .done("ok"))
        work.requestRun("a", reason: "Changed")
        work.update(idle(.sleeping))
        await waitUntilIdle(work)
        #expect(triggers == [.runNow, .request("Changed")])
    }

    /// Lets queued tasks run until nothing is running.
    @MainActor private func waitUntilIdle(_ work: BackgroundWork) async {
        for _ in 0..<200 where work.runningID != nil {
            await Task.yield()
        }
    }
}

/// A one-shot gate a test opens once it has set the scene.
@MainActor
private final class Signal {
    private var isFired = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        guard !isFired else { return }
        await withCheckedContinuation { waiters.append($0) }
    }

    func fire() {
        isFired = true
        waiters.forEach { $0.resume() }
        waiters = []
    }
}
