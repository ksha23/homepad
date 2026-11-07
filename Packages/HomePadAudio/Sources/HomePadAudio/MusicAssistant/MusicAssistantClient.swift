import Foundation
import HomePadCore
import os

/// Talks to Music Assistant through Home Assistant's `music_assistant` integration,
/// only by way of `services.smartHome` (`callService`, `callServiceForResponse` and
/// `integrationEntries`). HomePad never connects to Music Assistant itself.
@MainActor
struct MusicAssistantClient {
    /// Looks the smart home service up at call time, since another module installs it.
    let smartHome: @MainActor () -> any SmartHomeService
    /// The Music Assistant user searches, the library and playing are for: the
    /// recognized member's (`MusicAssistantService.use(user:)`), nil for none.
    var username: String?
    private let log = Log.make("MusicAssistant")

    init(smartHome: @escaping @MainActor () -> any SmartHomeService) {
        self.smartHome = smartHome
    }

    /// The running Music Assistant instance, or nil when Home Assistant has none set up.
    func entry() async throws -> SmartHomeIntegrationEntry? {
        let entries = try await smartHome().integrationEntries(domain: MusicAssistantAction.domain)
        return entries.first(where: \.isLoaded) ?? entries.first
    }

    func search(entryID: String, query: String, mediaTypes: [MAMediaItem.MediaType]? = nil,
                limit: Int = 8) async throws -> MASearchResults {
        MASearchResults(json: try await respond(.search(entryID: entryID, query: query, mediaTypes: mediaTypes, limit: limit,
                                                        username: username)))
    }

    func library(entryID: String, mediaType: MAMediaItem.MediaType, favorite: Bool? = nil,
                 orderBy: String? = nil, limit: Int = 25) async throws -> [MAMediaItem] {
        let response = try await respond(.library(entryID: entryID, mediaType: mediaType, favorite: favorite,
                                                  orderBy: orderBy, limit: limit, username: username))
        return MAMediaItem.list(response["items"])
    }

    /// The active queue of a player, or nil when it has none.
    func queue(entityID: String) async throws -> MAQueue? {
        MAQueue(response: try await respond(.getQueue(entityID: entityID)), entityID: entityID)
    }

    func play(_ mediaIDs: [String], mediaType: MAMediaItem.MediaType?, on entityID: String,
              enqueue: MusicAssistantAction.Enqueue = .replace, radioMode: Bool? = nil) async throws {
        try await send(.playMedia(entityID: entityID, mediaIDs: mediaIDs, mediaType: mediaType,
                                  enqueue: enqueue, radioMode: radioMode, username: username))
    }

    func transferQueue(from sourceEntityID: String?, to entityID: String) async throws {
        try await send(.transferQueue(to: entityID, from: sourceEntityID))
    }

    // MARK: Plumbing

    private func respond(_ action: MusicAssistantAction) async throws -> JSONValue {
        do {
            return try await smartHome().callServiceForResponse(
                domain: MusicAssistantAction.domain, service: action.service, data: action.data, target: action.target
            )
        } catch {
            log.error("\(action.service, privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
            throw error
        }
    }

    private func send(_ action: MusicAssistantAction) async throws {
        do {
            try await smartHome().callService(domain: MusicAssistantAction.domain, service: action.service, data: action.serviceData)
        } catch {
            log.error("\(action.service, privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
            throw error
        }
    }
}
