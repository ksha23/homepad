import Foundation
import HomePadCore

/// The Personal module's background tasks (`BackgroundWork`): photo sync,
/// calendars and reminders, and weather.
@MainActor
enum PersonalBackgroundTasks {
    static let photoSyncID = "personal.photoSync"
    static let calendarID = "personal.calendarSync"
    static let weatherID = "personal.weather"

    /// The library change observer asks for a sync on every change, so the
    /// schedule is only a backstop for changes it missed in the background.
    static let photoSyncInterval: TimeInterval = 60 * 60
    /// EventKit refreshes its own accounts too. This keeps subscribed
    /// calendars, such as a school feed, from waiting on the iPad's fetch setting.
    static let calendarInterval: TimeInterval = 15 * 60
    /// A failed forecast tries again sooner than the usual cadence.
    static let weatherRetryInterval: TimeInterval = 5 * 60

    static func register(in work: BackgroundWork, personal: PersonalServices) {
        let photos = personal.photos
        work.register(BackgroundTaskDescriptor(
            id: photoSyncID, title: "Photo Sync",
            summary: "Reads new photos as soon as they reach this iPad, and prepares album covers and the first screen of new photos, so Photos opens with them. It cannot make iCloud download sooner.",
            interval: { photoSyncInterval }, conditions: .displayIdle, systemLaunches: [.appRefresh, .processing],
            prepare: { [weak work] in
                photos.onAlbumsChanged = { work?.requestRun(photoSyncID, reason: "The photo library changed.") }
                photos.startSyncing()
            }
        ) { context in
            await photos.sync(context)
        })

        let calendar = personal.calendar
        work.register(BackgroundTaskDescriptor(
            id: calendarID, title: "Calendars and Reminders",
            summary: "Asks this iPad's iCloud, other and subscribed calendar accounts for changes, so Up Next, the faces and the glance stay current.",
            interval: { calendarInterval }, systemLaunches: .appRefresh
        ) { _ in
            calendar.refreshSources()
        })

        let weather = personal.weather
        work.register(BackgroundTaskDescriptor(
            id: weatherID, title: "Weather",
            summary: "Refreshes the forecast for the faces, widgets and Weather, on the cadence chosen in Personal Info.",
            interval: { weather.refreshInterval }, retryInterval: weatherRetryInterval, systemLaunches: .appRefresh
        ) { _ in
            await weather.scheduledRefresh()
        })
    }
}
