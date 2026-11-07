import HomePadUI
import SwiftUI

/// Chooses where the weather is for: the iPad's location or a searched city.
/// Used by the Weather app and the Personal Info settings pane. Tapping a
/// choice uses it.
struct PlacePickerSheet: View {
    @Environment(PersonalWeatherService.self) private var weather
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var results: [PlaceSearch.Result] = []
    @State private var isSearching = false

    var body: some View {
        SheetScreen("Weather Location") {
            VStack(spacing: Theme.Spacing.s) {
                GlassSearchField("City, zip code or address", text: $query)
                    .padding(.horizontal, Theme.Spacing.l)
                list
            }
        }
        .task(id: query) {
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled else { return }
            isSearching = true
            results = await PlaceSearch.search(query)
            isSearching = false
        }
    }

    private var list: some View {
        List {
            Section {
                Button {
                    dismiss()
                    Task { await weather.useCurrentLocation() }
                } label: {
                    Label("Use My Location", systemImage: "location.fill")
                }
            } footer: {
                Text("HomePad asks for your location once and uses it only for local weather.")
            }
            if !results.isEmpty {
                Section("Cities") {
                    ForEach(results) { result in
                        Button {
                            dismiss()
                            Task { await weather.choose(result.place) }
                        } label: {
                            VStack(alignment: .leading) {
                                Text(result.place.name).font(.headline)
                                if let detail = result.detail { Text(detail).font(.subheadline).foregroundStyle(.secondary) }
                            }
                        }
                        .foregroundStyle(.primary)
                    }
                }
            } else if isSearching {
                ProgressView().frame(maxWidth: .infinity)
            }
        }
    }
}
