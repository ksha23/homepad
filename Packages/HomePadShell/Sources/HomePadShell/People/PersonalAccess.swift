import HomePadCore
import HomePadUI

/// How much personal content the person in front of the screen may see.
enum PersonalAccess: Equatable {
    /// Nobody picked: personal apps and widgets are hidden.
    case guest
    /// A member was picked by hand but not recognized: personal items show locked.
    case selected
    /// Recognized by face or verified by Face ID: everything shows.
    case unlocked

    @MainActor
    init(_ household: Household) {
        if household.isPersonalContentUnlocked {
            self = .unlocked
        } else if household.isGuest {
            self = .guest
        } else {
            self = .selected
        }
    }

    enum Visibility: Equatable {
        case visible, locked, hidden
    }

    /// Visibility of an app or widget that is personal or shared.
    func visibility(isPersonal: Bool) -> Visibility {
        guard isPersonal else { return .visible }
        switch self {
        case .guest: return .hidden
        case .selected: return .locked
        case .unlocked: return .visible
        }
    }

    /// The icon badge for an app, or nil when the app should be hidden.
    @MainActor func badge(for app: AppDescriptor) -> AppIconTile.Badge? {
        switch visibility(isPersonal: app.requiresRecognizedMember) {
        case .visible: return app.countBadge
        case .locked: return .locked
        case .hidden: return nil
        }
    }
}
