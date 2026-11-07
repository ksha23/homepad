import HomePadCore
import HomePadUI
import SwiftUI

/// Settings > Background Tasks: every task modules registered with
/// `BackgroundWork`, with its last run and result, when it runs next or what
/// it waits for, how often and under which conditions, and Run Now.
///
/// Each fact is a title over its value, since values run to a sentence.
struct BackgroundTasksPane: View {
    @Environment(AppServices.self) private var services
    /// Times read as words ("in 12 minutes"), so they move on once a minute while the pane shows.
    @State private var now = Date()

    var body: some View {
        let work = services.backgroundWork
        Form {
            Section {
                Text("HomePad does this work while it is on screen and nobody is using it, one task at a time, and never while an app opens or right after a touch. While HomePad is in the background, iOS decides when it may run, usually at night on power.")
                    .foregroundStyle(.secondary)
            }
            if work.tasks.isEmpty {
                Text("No module has background tasks.").foregroundStyle(.secondary)
            }
            ForEach(work.tasks) { task in
                BackgroundTaskSection(task: task, work: work, now: now)
            }
        }
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(60))
                now = Date()
            }
        }
    }
}

/// One task's section.
private struct BackgroundTaskSection: View {
    let task: BackgroundTaskDescriptor
    let work: BackgroundWork
    let now: Date

    var body: some View {
        let record = work.record(for: task.id)
        Section {
            fact("Last Run", record.lastRun.map { Self.time($0, now: now) } ?? "Not yet")
            if let outcome = record.outcome, record.lastFinished != nil {
                fact("Result: \(outcome.title)", outcome.detail, isProblem: outcome.isProblem)
            }
            fact("Next Run", nextRunText(record))
            fact("Runs", Self.schedule(task))
            Button("Run Now") { work.runNow(task.id) }
                .disabled(work.runningID == task.id || work.isWaitingToRunNow(task.id))
        } header: {
            Text(task.title)
        } footer: {
            Text(task.summary)
        }
    }

    private func fact(_ title: String, _ value: String, isProblem: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            Text(title).foregroundStyle(isProblem ? AnyShapeStyle(.red) : AnyShapeStyle(.primary))
            Text(value).font(.subheadline).foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }

    private func nextRunText(_ record: BackgroundTaskRecord) -> String {
        if work.runningID == task.id { return "Running now" }
        if work.isWaitingToRunNow(task.id) { return "After the task running now" }
        guard work.isStarted else { return "Not on this device" }
        guard let next = work.nextRun(for: task.id) else { return "Not scheduled" }
        if next > now { return Self.time(next, now: now) }
        if let blocker = work.blocker(for: task.id) { return "Due, waiting for \(blocker.waitingFor)" }
        if let reason = record.request { return "Due: \(reason)" }
        return "Due now"
    }

    /// "in 12 minutes, 3:42 PM" or "5 minutes ago, 3:25 PM".
    private static func time(_ date: Date, now: Date) -> String {
        let relative = date.formatted(.relative(presentation: .named, unitsStyle: .wide))
        return "\(relative), \(date.formatted(date: .omitted, time: .shortened))"
    }

    /// "Every hour, while nobody is using the screen. In the background: app refresh and processing."
    private static func schedule(_ task: BackgroundTaskDescriptor) -> String {
        var text = "Every \(interval(task.interval()))"
        var conditions: [String] = []
        if task.conditions.contains(.displayIdle) { conditions.append("while nobody is using the screen") }
        if task.conditions.contains(.displayAsleep) { conditions.append("while the screen sleeps") }
        if task.conditions.contains(.onPower) { conditions.append("on power") }
        if !conditions.isEmpty { text += ", " + conditions.formatted(.list(type: .and)) }
        var launches: [String] = []
        if task.systemLaunches.contains(.appRefresh) { launches.append("app refresh") }
        if task.systemLaunches.contains(.processing) { launches.append("processing") }
        text += launches.isEmpty ? ". Only while HomePad is on screen." : ". In the background: \(launches.formatted(.list(type: .and)))."
        return text
    }

    /// "15 minutes", "hour", "2 hours".
    private static func interval(_ seconds: TimeInterval) -> String {
        let minutes = Int((seconds / 60).rounded())
        if minutes == 60 { return "hour" }
        if minutes % 60 == 0 { return "\(minutes / 60) hours" }
        return minutes == 1 ? "minute" : "\(minutes) minutes"
    }
}

private extension BackgroundTaskOutcome {
    var isProblem: Bool {
        if case .failed = self { return true }
        return false
    }
}
