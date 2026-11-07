import HomePadCore
import SwiftUI

/// Weather location, units and refresh cadence.
struct WeatherSettingsSection: View {
    @Environment(PersonalWeatherService.self) private var weather
    @Environment(SettingsStore.self) private var settings
    @State private var isPickingPlace = false

    var body: some View {
        Section {
            Button {
                isPickingPlace = true
            } label: {
                LabeledContent("Location", value: locationText)
            }
            .foregroundStyle(.primary)
            // On the row, not the section: a section hands its modifiers to
            // every row, and several sheets on one binding present none.
            .sheet(isPresented: $isPickingPlace) {
                PlacePickerSheet()
            }
            Picker("Units", selection: settings.binding(PersonalSettings.weatherUnits)) {
                ForEach(WeatherUnitSystem.allCases, id: \.self) { Text($0.title).tag($0) }
            }
            Picker("Refresh", selection: settings.binding(PersonalSettings.weatherRefreshMinutes)) {
                Text("Every 15 Minutes").tag(15)
                Text("Every 30 Minutes").tag(30)
                Text("Every Hour").tag(60)
            }
            if let source = weather.forecast?.source {
                LabeledContent("Source", value: source.displayName)
            }
        } header: {
            Text("Weather")
        } footer: {
            Text("HomePad uses Apple Weather when it is available and switches to Open-Meteo automatically when it is not.")
        }
    }

    private var locationText: String {
        switch weather.locationChoice {
        case .undecided: "Not Set"
        case .current: "My Location"
        case .place(let place): place.name
        }
    }
}
