import HomePadCore
import Observation

/// Loads and saves each member's Home Screen layout through `SettingsStore`
/// (guests share one). Until someone edits their screen, they get the default
/// layout built from whatever modules registered.
@MainActor
@Observable
final class HomeScreenLayoutStore {
    @ObservationIgnored private let settings: SettingsStore
    @ObservationIgnored private let registry: ModuleRegistry

    init(settings: SettingsStore, registry: ModuleRegistry) {
        self.settings = settings
        self.registry = registry
    }

    /// The member's layout, with any newly registered apps appended.
    func layout(for memberID: HouseholdMember.ID?) -> HomeScreenLayout {
        let stored = settings[ShellSettings.homeScreenLayout(for: memberID)] ?? defaultLayout()
        return stored.reconciled(withAppIDs: registry.apps.map(\.id))
    }

    /// Applies an edit and saves it.
    func update(for memberID: HouseholdMember.ID?, _ change: (inout HomeScreenLayout) -> Void) {
        var layout = layout(for: memberID)
        change(&layout)
        settings[ShellSettings.homeScreenLayout(for: memberID)] = layout
    }

    /// Back to the default layout.
    func reset(for memberID: HouseholdMember.ID?) {
        settings.reset(ShellSettings.homeScreenLayout(for: memberID))
    }

    private func defaultLayout() -> HomeScreenLayout {
        HomeScreenLayout.makeDefault(
            appIDs: registry.apps.map(\.id),
            widgets: registry.widgets.map { ($0.id, $0.supportedSizes) }
        )
    }
}
