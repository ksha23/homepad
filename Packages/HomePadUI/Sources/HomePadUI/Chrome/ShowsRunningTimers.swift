import SwiftUI

/// True when the screen on top shows its running timers itself, so the shell
/// leaves the timer pill out of the top of the screen, as it leaves the Now
/// Playing pill out of Music. Set it with `.showsRunningTimers()`.
public struct ShowsRunningTimersKey: PreferenceKey {
    public static let defaultValue = false
    public static func reduce(value: inout Bool, nextValue: () -> Bool) {
        value = value || nextValue()
    }
}

public extension View {
    /// Tells the shell this screen shows the running timers, such as cooking
    /// mode's header, so the timer pill at the top of the screen steps aside
    /// while it is on screen.
    ///
    ///     DetailHeader(recipe.title) { RunningTimerPills() }
    ///         .showsRunningTimers()
    func showsRunningTimers(_ shows: Bool = true) -> some View {
        preference(key: ShowsRunningTimersKey.self, value: shows)
    }
}
