import HomePadCore
import HomePadUI

extension AppDescriptor {
    /// The red count on the app's icon, or none when the app has nothing to count.
    /// Read inside a view body, so a change in the app's model redraws the icon.
    @MainActor var countBadge: AppIconTile.Badge {
        guard let count = badgeCount?(), count > 0 else { return .none }
        return .count(count)
    }
}
