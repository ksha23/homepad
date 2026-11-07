#if os(iOS)
import BackgroundTasks
import Foundation
import UIKit

/// The launches iOS gives HomePad while it is in the background, through
/// `BGTaskScheduler`. There are two identifiers, not one per task, so the
/// Info.plist list stays fixed as modules add tasks: each launch runs every
/// due task that allows that kind of launch, one after another.
public extension BackgroundWork {
    /// The identifiers in Info.plist's `BGTaskSchedulerPermittedIdentifiers`,
    /// after the bundle identifier (`$(PRODUCT_BUNDLE_IDENTIFIER)` there).
    static let refreshSuffix = ".background.refresh"
    static let processingSuffix = ".background.processing"

    /// Registers the two launches with iOS. Call during launch, before the
    /// app finishes launching, which a module's `register` is.
    func registerSystemLaunches() {
        guard let bundleID = Bundle.main.bundleIdentifier else { return }
        for (suffix, kind) in [(Self.refreshSuffix, SystemBackgroundLaunches.appRefresh), (Self.processingSuffix, .processing)] {
            let registered = BGTaskScheduler.shared.register(forTaskWithIdentifier: bundleID + suffix, using: .main) { [weak self] task in
                MainActor.assumeIsolated { self?.handleSystemLaunch(task, kind: kind) }
            }
            if !registered { log.error("Could not register \(suffix, privacy: .public), check BGTaskSchedulerPermittedIdentifiers") }
        }
    }

    /// Asks iOS for the next launches, from the soonest due task of each
    /// kind. The shell calls it as HomePad leaves the screen, and each launch
    /// asks again when it ends. iOS decides when they actually come.
    func scheduleSystemLaunches() {
        guard let bundleID = Bundle.main.bundleIdentifier else { return }
        let scheduler = BGTaskScheduler.shared
        if let date = soonestRun(allowing: .appRefresh) {
            let request = BGAppRefreshTaskRequest(identifier: bundleID + Self.refreshSuffix)
            request.earliestBeginDate = date
            submit(request, to: scheduler)
        }
        if let date = soonestRun(allowing: .processing) {
            let request = BGProcessingTaskRequest(identifier: bundleID + Self.processingSuffix)
            request.earliestBeginDate = date
            // Every task HomePad has reads from the network: iCloud photos, calendars, weather, music.
            request.requiresNetworkConnectivity = true
            request.requiresExternalPower = tasks.contains { $0.systemLaunches.contains(.processing) && $0.conditions.contains(.onPower) }
            submit(request, to: scheduler)
        }
    }

    private func submit(_ request: BGTaskRequest, to scheduler: BGTaskScheduler) {
        do {
            try scheduler.submit(request)
        } catch {
            // The simulator always refuses, and so does an iPad with Background App Refresh off.
            log.notice("Background launch not scheduled: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func soonestRun(allowing launch: SystemBackgroundLaunches) -> Date? {
        tasks.filter { !$0.systemLaunches.isDisjoint(with: launch) }.compactMap { nextRun(for: $0.id) }.min()
    }

    private func handleSystemLaunch(_ systemTask: BGTask, kind: SystemBackgroundLaunches) {
        let device = UIDevice.current
        device.isBatteryMonitoringEnabled = true
        let onPower = device.batteryState == .charging || device.batteryState == .full
        isInSystemLaunch = true
        apply(.systemLaunch(isOnPower: onPower))
        start()
        let runner = Task { @MainActor [weak self] in
            guard let self else { return }
            while !Task.isCancelled, let id = self.nextDueTask(allowing: kind), let run = self.start(id, trigger: .system) {
                await run.value
            }
            self.isInSystemLaunch = false
            self.scheduleSystemLaunches()
            systemTask.setTaskCompleted(success: true)
        }
        systemTask.expirationHandler = { [weak self] in
            Task { @MainActor in
                runner.cancel()
                self?.expireCurrentRun()
            }
        }
    }
}
#endif
