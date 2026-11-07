import Foundation
import HomePadCore

/// Decides which providers answer a request, in order: the request's own
/// choice, the person's choice, the household default, the fallback order,
/// then any other ready provider. Unready providers are skipped.
@MainActor
struct ProviderRouter {
    let store: ProviderStore
    let household: Household

    func candidates(requested: String?) -> [ProviderConfig] {
        let preferences = household.activeMember.map(MemberAssistantPreferences.init(member:))
        let ids = Self.order(
            requested: requested, personal: preferences?.providerID,
            householdDefault: store.settings[AssistantSettings.defaultProvider],
            fallback: store.settings[AssistantSettings.fallbackOrder],
            all: Self.unchosenOrder(ProviderCatalog.all) { store.apiKey(for: $0) != nil }
        )
        return ids.compactMap { id -> ProviderConfig? in
            guard let descriptor = ProviderCatalog.descriptor(id), store.status(of: descriptor).isReady else { return nil }
            let personalModel = preferences?.providerID == id ? preferences?.model : nil
            return store.config(for: descriptor, model: personalModel)
        }
    }

    /// The provider that would answer next, for labels such as "Ask Claude".
    var preferred: ProviderDescriptor? {
        candidates(requested: nil).first?.descriptor
    }

    /// With nothing chosen, providers the person added a key for come before
    /// Apple's on-device model. The new iPad had Claude set up, yet the smaller
    /// on-device model answered first and kept asking what kind of music to play.
    static func unchosenOrder(_ descriptors: [ProviderDescriptor], hasKey: (ProviderDescriptor) -> Bool) -> [String] {
        let keyed = descriptors.filter { $0.requiresAPIKey && hasKey($0) }.map(\.id)
        return keyed + descriptors.map(\.id).filter { !keyed.contains($0) }
    }

    /// Pure ordering rule, deduplicated, empty IDs ignored.
    static func order(requested: String?, personal: String?, householdDefault: String, fallback: [String], all: [String]) -> [String] {
        var seen = Set<String>()
        return ([requested, personal, householdDefault].compactMap { $0 } + fallback + all).filter { id in
            !id.isEmpty && seen.insert(id).inserted
        }
    }
}
