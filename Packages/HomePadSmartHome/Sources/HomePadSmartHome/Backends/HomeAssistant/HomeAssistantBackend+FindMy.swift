import Foundation
import HAKit
import HomePadCore

extension HomeAssistantBackend {
    /// Plays a sound on a tracked device through `icloud.play_sound` or a
    /// critical Companion app notification (see `HAPlaySoundCall`).
    func playSound(on device: TrackedDevice) async throws {
        guard connection != nil, status.isConnected else { throw SmartHomeError.notConnected(.homeAssistant) }
        let entityID = BackendID.localID(of: device.id)
        let accounts = registry.platform(of: entityID) == "icloud" ? try await iCloudAccounts() : []
        let call = try HAPlaySoundCall.call(entityID: entityID, state: states[entityID], registry: registry, iCloudAccounts: accounts)
        try await execute(call)
    }

    /// The iCloud integration's accounts, from `config_entries/get`. Each entry's
    /// title is its Apple Account, which `icloud.play_sound` takes as `account`.
    private func iCloudAccounts() async throws -> [SmartHomeIntegrationEntry] {
        guard let connection else { throw SmartHomeError.notConnected(.homeAssistant) }
        do {
            let result = JSONValue(haData: try await connection.send(
                HARequests.command(SmartHomeCommandType.configEntries, data: ["domain": "icloud"])
            ))
            return (result.arrayValue ?? []).compactMap(SmartHomeIntegrationEntry.init(json:))
        } catch {
            throw SmartHomeError.backend(error.localizedDescription)
        }
    }
}
