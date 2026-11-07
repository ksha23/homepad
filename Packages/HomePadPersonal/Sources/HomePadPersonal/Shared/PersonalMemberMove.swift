import Foundation
import HomePadCore

/// Keeps what this iPad assigned to a person theirs when they take the ID the
/// household knows them by, as this HomePad joins a household that already
/// had them: the calendars and reminder lists that are theirs, the calendars
/// they unchecked, and the Find My devices that are theirs. These stay on this
/// iPad, since calendar identifiers differ from iPad to iPad.
@MainActor
enum PersonalMemberMove {
    static func register(services: AppServices) {
        let settings = services.settings
        services.household.onMemberIDChange { old, new in
            move(from: old, to: new, settings: settings)
        }
    }

    static func move(from old: UUID, to new: UUID, settings: SettingsStore) {
        let audiences = settings[PersonalSettings.calendarAudiences]
        let movedAudiences = audiences.mapValues { audience -> CalendarAudience in
            guard case .members(var ids) = audience, ids.remove(old) != nil else { return audience }
            ids.insert(new)
            return .members(ids)
        }
        if movedAudiences != audiences { settings[PersonalSettings.calendarAudiences] = movedAudiences }

        var unchecked = settings[PersonalSettings.uncheckedCalendars]
        if let calendars = unchecked.removeValue(forKey: old.uuidString) {
            unchecked[new.uuidString] = calendars
            settings[PersonalSettings.uncheckedCalendars] = unchecked
        }

        let owners = settings[PersonalSettings.findMyOwners]
        let movedOwners = owners.mapValues { $0 == .member(old) ? FindMyOwnerChoice.member(new) : $0 }
        if movedOwners != owners { settings[PersonalSettings.findMyOwners] = movedOwners }
    }
}
