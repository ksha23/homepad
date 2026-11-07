import HomePadCore
import Observation
import SwiftUI

/// The view and date Calendar shows.
struct CalendarFocus: Equatable {
    var mode: CalendarDisplayMode
    var date: Date
}

/// What Calendar and Photos show, for the assistant. The apps keep it current
/// with `reportsScreenFocus(_:at:)`, and nothing reads it until someone asks.
@MainActor
@Observable
final class PersonalScreenFocus {
    @ObservationIgnored var calendar: CalendarFocus?
    @ObservationIgnored var album: PhotoAlbum?
}

/// The day in Calendar and the open album in Photos, for the assistant. Both
/// are personal, so the assistant leaves them out unless someone is recognized.
/// The album is named only when the person asking may see it
/// (`PhotoAccessPolicy`), so it never outlives the person it was opened for.
@MainActor
enum PersonalScreenContext {
    static func register(in registry: ModuleRegistry, focus: PersonalScreenFocus, photoAccess: @escaping @MainActor () -> PhotoAccessPolicy) {
        registry.register(screenContext: ScreenContextProvider(appID: "calendar", isPersonal: true) { calendarSummary(focus.calendar) })
        registry.register(screenContext: ScreenContextProvider(appID: "photos", isPersonal: true) {
            albumSummary(focus.album, access: photoAccess())
        })
    }

    /// "The album Summer Trips is open.", or nil when the person asking may not see that album.
    static func albumSummary(_ album: PhotoAlbum?, access: PhotoAccessPolicy) -> String? {
        guard let album, access.allows(album.source) else { return nil }
        return "The album \(album.title) is open."
    }

    /// "The Day view of Thursday, October 22, 2026."
    static func calendarSummary(_ focus: CalendarFocus?) -> String? {
        guard let focus else { return nil }
        let day = focus.date.formatted(date: .complete, time: .omitted)
        switch focus.mode {
        case .day: return "The Day view of \(day)."
        case .week: return "The Week view, around \(day)."
        case .month: return "The Month view of \(focus.date.formatted(.dateTime.month(.wide).year()))."
        }
    }
}

extension View {
    /// Keeps one part of `PersonalScreenFocus` in step with what this screen shows, and clears it when the screen goes.
    func reportsScreenFocus<Value: Equatable>(_ value: Value?, at keyPath: ReferenceWritableKeyPath<PersonalScreenFocus, Value?>) -> some View {
        modifier(PersonalScreenFocusReporter(value: value, keyPath: keyPath))
    }
}

private struct PersonalScreenFocusReporter<Value: Equatable>: ViewModifier {
    let value: Value?
    let keyPath: ReferenceWritableKeyPath<PersonalScreenFocus, Value?>
    @Environment(PersonalScreenFocus.self) private var focus: PersonalScreenFocus?

    func body(content: Content) -> some View {
        content
            .onChange(of: value, initial: true) { focus?[keyPath: keyPath] = value }
            .onDisappear { focus?[keyPath: keyPath] = nil }
    }
}
