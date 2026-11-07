import Foundation
import HomePadCore

/// Searches the free, community-run Radio Browser directory (radio-browser.info).
/// No account or key. The API asks clients to send a descriptive User-Agent
/// and to report plays through the click endpoint, which this client does.
struct RadioBrowserClient: Sendable {
    /// Public mirrors, tried in order.
    static let mirrors = ["de1.api.radio-browser.info", "de2.api.radio-browser.info"]
    private static let userAgent = "HomePad/0.1 (iPad smart display)"

    var session: URLSession = .shared

    /// Stations whose name matches, topped up with stations tagged with the term
    /// ("jazz", "lofi"), most popular first.
    func search(_ term: String, limit: Int = 30) async throws -> [RadioStation] {
        let query = term.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return [] }
        let byName = try await stations(path: "/json/stations/search", query: Self.searchItems(name: query, limit: limit))
        guard byName.count < limit / 2 else { return byName }
        let byTag = (try? await stations(path: "/json/stations/search", query: Self.searchItems(tag: query, limit: limit))) ?? []
        return Self.merge(byName, byTag, limit: limit)
    }

    /// Tells the directory a station was played. Failures are ignored.
    func reportPlay(of station: RadioStation) async {
        guard station.origin == .radioBrowser, station.id.hasPrefix("rb:") else { return }
        let uuid = String(station.id.dropFirst(3))
        _ = try? await data(path: "/json/url/\(uuid)", query: [])
    }

    // MARK: Request building (pure, tested)

    static func searchItems(name: String? = nil, tag: String? = nil, limit: Int) -> [URLQueryItem] {
        var items = [
            URLQueryItem(name: "limit", value: String(limit)),
            URLQueryItem(name: "hidebroken", value: "true"),
            URLQueryItem(name: "order", value: "clickcount"),
            URLQueryItem(name: "reverse", value: "true"),
        ]
        if let name { items.append(URLQueryItem(name: "name", value: name)) }
        if let tag { items.append(URLQueryItem(name: "tag", value: tag.lowercased())) }
        return items
    }

    /// Name matches first, then tag matches that are not already present.
    static func merge(_ primary: [RadioStation], _ secondary: [RadioStation], limit: Int) -> [RadioStation] {
        var seen = Set(primary.map(\.id))
        let extra = secondary.filter { seen.insert($0.id).inserted }
        return Array((primary + extra).prefix(limit))
    }

    // MARK: Networking

    private func stations(path: String, query: [URLQueryItem]) async throws -> [RadioStation] {
        try RadioBrowserParser.stations(from: try await data(path: path, query: query))
    }

    private func data(path: String, query: [URLQueryItem]) async throws -> Data {
        var lastError: Error = URLError(.cannotFindHost)
        for host in Self.mirrors {
            var components = URLComponents()
            components.scheme = "https"
            components.host = host
            components.path = path
            components.queryItems = query.isEmpty ? nil : query
            guard let url = components.url else { continue }
            var request = URLRequest(url: url, timeoutInterval: 10)
            request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
            do {
                let (data, response) = try await session.data(for: request)
                if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                    lastError = URLError(.badServerResponse)
                    continue
                }
                return data
            } catch {
                lastError = error
            }
        }
        throw lastError
    }
}
