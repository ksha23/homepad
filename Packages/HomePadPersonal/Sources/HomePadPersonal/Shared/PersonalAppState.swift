import Foundation
import HomePadCore

/// What the Personal apps keep between openings (see `@AppState`). Each is
/// kept for the recognized member, with one shared value while nobody is
/// recognized, so one person's open list, album or device never shows
/// for someone else. Weather and World Clock keep their place in settings.
enum PersonalAppState {
    /// Day, week or month.
    static let calendarMode = AppStateKey("calendar.mode", default: CalendarDisplayMode.day, scope: .member)
    /// The day Calendar shows. A time position: after a few hours, or the next
    /// day, Calendar opens on today in the view it was left in.
    static let calendarDate = AppStateKey("calendar.date", default: Date(), scope: .member, lifetime: .timePosition)
    /// The smart list or list Reminders shows. Nil opens on Today when
    /// something is due, else All.
    static let reminderList = AppStateKey<ReminderSelection?>("reminders.list", default: nil, scope: .member)
    /// The open album, by identifier.
    static let photosAlbum = AppStateKey<String?>("photos.album", default: nil, scope: .member)
    /// The photo at the top of the open album's grid, for this launch.
    static let photosGridTop = AppStateKey<PhotoGridPosition?>("photos.gridTop", default: nil, scope: .member, storage: .session)
    /// The device whose card Find My shows.
    static let findMyDevice = AppStateKey<TrackedDevice.ID?>("findmy.device", default: nil, scope: .member)
    /// Where the map was left with no device selected, for this launch.
    static let findMyRegion = AppStateKey<FindMyMapRegion?>("findmy.region", default: nil, scope: .member, storage: .session)
}

/// The top photo of an album's grid.
struct PhotoGridPosition: Codable, Equatable, Sendable {
    var albumID: String
    var photoID: String
}
