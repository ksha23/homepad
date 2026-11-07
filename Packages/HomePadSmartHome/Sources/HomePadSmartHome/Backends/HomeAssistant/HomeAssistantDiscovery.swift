import Foundation
import HomePadCore
import Network
import Observation

/// Finds Home Assistant instances on the local network over Bonjour (`_home-assistant._tcp`).
/// Runs only while the Settings pane is open, so the local network prompt appears
/// when the person is setting things up.
@MainActor
@Observable
final class HomeAssistantDiscovery {
    struct Instance: Identifiable, Hashable, Sendable {
        var id: String
        var name: String
        var url: URL
        var version: String?
    }

    private(set) var instances: [Instance] = []
    private(set) var isSearching = false
    @ObservationIgnored private var browser: NWBrowser?

    func start() {
        guard browser == nil else { return }
        let browser = NWBrowser(for: .bonjourWithTXTRecord(type: "_home-assistant._tcp", domain: nil), using: .tcp)
        browser.browseResultsChangedHandler = { [weak self] results, _ in
            // One instance can be advertised on several interfaces, so keep one per ID.
            let found = Dictionary(results.compactMap(Self.instance(from:)).map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            Task { @MainActor in self?.instances = found.values.sorted { $0.name < $1.name } }
        }
        browser.stateUpdateHandler = { [weak self] state in
            let searching: Bool
            switch state {
            case .ready, .setup: searching = true
            default: searching = false
            }
            Task { @MainActor in self?.isSearching = searching }
        }
        browser.start(queue: .main)
        self.browser = browser
    }

    func stop() {
        browser?.cancel()
        browser = nil
        isSearching = false
    }

    nonisolated private static func instance(from result: NWBrowser.Result) -> Instance? {
        guard case .service(let name, _, _, _) = result.endpoint else { return nil }
        var txt: [String: String] = [:]
        if case .bonjour(let record) = result.metadata { txt = record.dictionary }
        return instance(serviceName: name, txt: txt)
    }

    /// Builds an instance from a Bonjour TXT record. Home Assistant publishes
    /// `internal_url`, `base_url`, `location_name`, `uuid` and `version`.
    nonisolated static func instance(serviceName: String, txt: [String: String]) -> Instance? {
        let candidates = [txt["internal_url"], txt["base_url"], txt["external_url"]].compactMap { $0 }.filter { !$0.isEmpty }
        guard let url = candidates.lazy.compactMap(HomeAssistantConfiguration.normalizedURL(from:)).first else { return nil }
        let name = txt["location_name"].flatMap { $0.isEmpty ? nil : $0 } ?? serviceName
        return Instance(id: txt["uuid"] ?? url.absoluteString, name: name, url: url, version: txt["version"])
    }
}
