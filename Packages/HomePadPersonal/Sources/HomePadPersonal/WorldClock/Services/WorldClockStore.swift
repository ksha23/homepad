import Foundation
import HomePadCore
import Observation

/// The household's World Clock cities and style, kept in settings (and synced
/// through iCloud key-value storage to other HomePads).
@MainActor
@Observable
public final class WorldClockStore {
    @ObservationIgnored private let settings: SettingsStore

    public init(settings: SettingsStore) {
        self.settings = settings
    }

    public var cities: [WorldClockCity] { settings[PersonalSettings.worldClockCities] }

    public var style: WorldClockStyle {
        get { settings[PersonalSettings.worldClockStyle] }
        set { settings[PersonalSettings.worldClockStyle] = newValue }
    }

    /// Adds a city unless one with the same name and zone is already there.
    public func add(_ city: WorldClockCity) {
        guard !cities.contains(city) else { return }
        settings[PersonalSettings.worldClockCities].append(city)
    }

    public func remove(_ city: WorldClockCity) {
        settings[PersonalSettings.worldClockCities].removeAll { $0 == city }
    }

    public func remove(atOffsets offsets: IndexSet) {
        settings[PersonalSettings.worldClockCities].remove(atOffsets: offsets)
    }

    public func move(fromOffsets source: IndexSet, toOffset destination: Int) {
        settings[PersonalSettings.worldClockCities].move(fromOffsets: source, toOffset: destination)
    }

    /// A saved city first, then the offline catalog, for the assistant.
    public func lookup(_ name: String) -> WorldClockCity? {
        cities.first { $0.name.localizedCaseInsensitiveCompare(name) == .orderedSame } ?? CityCatalog.bestMatch(name)
    }
}
