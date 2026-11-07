import HomePadUI
import SwiftUI

/// Searches cities to add to the World Clock: the offline catalog first, then
/// MapKit for places that are not time zone names. Tapping a city adds it.
struct AddCitySheet: View {
    @Environment(WorldClockStore.self) private var clocks
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var mapResults: [WorldClockCity] = []

    var body: some View {
        SheetScreen("Add City") {
            VStack(spacing: Theme.Spacing.s) {
                GlassSearchField("City", text: $query)
                    .padding(.horizontal, Theme.Spacing.l)
                list
            }
        }
        .task(id: query) {
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled, query.count >= 3 else { mapResults = []; return }
            mapResults = await PlaceSearch.search(query).compactMap { result in
                result.place.timeZoneID.map { WorldClockCity(name: result.place.name, timeZoneID: $0) }
            }
        }
    }

    /// The matching cities, each with its time now.
    private var list: some View {
        List {
            let local = CityCatalog.search(query)
            ForEach(local + mapResults.filter { !local.contains($0) }) { city in
                Button {
                    clocks.add(city)
                    dismiss()
                } label: {
                    HStack {
                        VStack(alignment: .leading) {
                            Text(city.name).font(.headline)
                            Text(city.timeZone.localizedName(for: .generic, locale: .current) ?? city.timeZoneID)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(TimeZoneMath.timeText(at: Date(), in: city.timeZone))
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                }
                .foregroundStyle(.primary)
                .disabled(clocks.cities.contains(city))
            }
        }
        .overlay {
            if query.isEmpty {
                ContentUnavailableView("Add a City", systemImage: "globe", description: Text("Search for a city to see its time."))
            }
        }
    }
}
