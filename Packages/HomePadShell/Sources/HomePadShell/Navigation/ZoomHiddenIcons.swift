import Observation

/// Which app icon is hidden while its app zooms out of it or into it, the window being the icon then.
/// Each icon has an observable flag of its own, so hiding an icon or showing it again updates that icon
/// alone. Read as one shared value, it made every tile on the Home Screen evaluate its body again at each
/// zoom's start and landing, about 8 ms of the main thread each time in the simulator.
@MainActor
final class ZoomHiddenIcons {
    /// One icon's flag.
    @MainActor
    @Observable
    final class Flag {
        var isHidden = false
    }

    private var flags: [String: Flag] = [:]
    private var hiddenKey: String?

    /// Hides the icon recorded under `key` and shows the one hidden before. Nil shows every icon.
    func hide(_ key: String?) {
        guard key != hiddenKey else { return }
        if let hiddenKey { flags[hiddenKey]?.isHidden = false }
        hiddenKey = key
        if let key { flag(key).isHidden = true }
    }

    /// Whether the icon recorded under `key` is hidden. A view that reads it updates when it changes.
    func isHidden(_ key: String) -> Bool {
        flag(key).isHidden
    }

    private func flag(_ key: String) -> Flag {
        if let flag = flags[key] { return flag }
        let flag = Flag()
        flags[key] = flag
        return flag
    }
}
