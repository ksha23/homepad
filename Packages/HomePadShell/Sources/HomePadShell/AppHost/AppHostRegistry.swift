import Foundation

/// The apps' hosts, by app ID. The navigator shows what the app on screen presents, and hides what every
/// other app presents, in the same moment the zoom's picture comes or goes, so a cover never hides the
/// zoom and never shows over another screen.
@MainActor
final class AppHostRegistry {
    private struct Entry {
        weak var host: SuspendableHostController?
    }

    private var entries: [String: Entry] = [:]
    /// The app whose presentations show, nil for none.
    private var shownAppID: String?
    /// Told the ID of an app whose presentations were dismissed as it was suspended.
    var onDismissPresentations: (String) -> Void = { _ in }

    func register(_ host: SuspendableHostController, for appID: String) {
        entries = entries.filter { $0.value.host != nil }
        entries[appID] = Entry(host: host)
        host.showsPresentations = appID == shownAppID
        host.onDismissPresentations = { [weak self] in self?.onDismissPresentations(appID) }
    }

    /// Shows what `appID` presents and hides what the others present. Nil hides them all.
    func showPresentations(of appID: String?) {
        shownAppID = appID
        for (id, entry) in entries {
            entry.host?.showsPresentations = id == appID
        }
    }
}
