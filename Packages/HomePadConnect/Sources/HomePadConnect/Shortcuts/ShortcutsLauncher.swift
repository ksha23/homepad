import Foundation
import HomePadCore
import Observation
#if canImport(UIKit)
import UIKit
#endif

/// Runs the household's favorite Shortcuts by name through the Shortcuts app
/// (`shortcuts://run-shortcut?name=`). The list is synced through iCloud settings.
@MainActor
@Observable
public final class ShortcutsLauncher {
    @ObservationIgnored private let services: AppServices
    public private(set) var lastError: String?

    init(services: AppServices) {
        self.services = services
    }

    public var names: [String] { services.settings[ConnectSettings.shortcutNames] }

    public func add(_ name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !names.contains(trimmed) else { return }
        services.settings[ConnectSettings.shortcutNames] = names + [trimmed]
    }

    public func remove(_ name: String) {
        services.settings[ConnectSettings.shortcutNames] = names.filter { $0 != name }
    }

    public func move(from source: IndexSet, to destination: Int) {
        var updated = names
        updated.move(fromOffsets: source, toOffset: destination)
        services.settings[ConnectSettings.shortcutNames] = updated
    }

    /// Opens the Shortcuts app to run `name`. Returns false when it could not.
    @discardableResult
    public func run(_ name: String) async -> Bool {
        lastError = nil
        guard let url = Self.url(for: name) else { return false }
        #if canImport(UIKit)
        let opened = await UIApplication.shared.open(url)
        if !opened { lastError = "Install the Shortcuts app to run \"\(name)\"." }
        return opened
        #else
        return false
        #endif
    }

    /// The Shortcuts URL that runs a shortcut by name.
    public static func url(for name: String) -> URL? {
        var components = URLComponents()
        components.scheme = "shortcuts"
        components.host = "run-shortcut"
        components.queryItems = [URLQueryItem(name: "name", value: name)]
        return components.url
    }
}
