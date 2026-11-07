import SwiftUI

/// World Clock cities (reorder, delete, add) and the clock style.
struct WorldClockSettingsSection: View {
    @Environment(WorldClockStore.self) private var clocks
    @State private var isAdding = false

    var body: some View {
        Section {
            @Bindable var clocks = clocks
            Picker("Clock Style", selection: $clocks.style) {
                ForEach(WorldClockStyle.allCases, id: \.self) { Text($0.title).tag($0) }
            }
            ForEach(clocks.cities) { city in
                LabeledContent(city.name, value: TimeZoneMath.timeText(at: Date(), in: city.timeZone))
            }
            .onDelete { clocks.remove(atOffsets: $0) }
            .onMove { clocks.move(fromOffsets: $0, toOffset: $1) }
            Button("Add City") { isAdding = true }
                // On the row, not the section: a section hands its modifiers
                // to every row, and several sheets on one binding present none.
                .sheet(isPresented: $isAdding) {
                    AddCitySheet()
                }
        } header: {
            Text("World Clock")
        } footer: {
            Text("Swipe a city to remove it. Cities sync to your other HomePads through iCloud.")
        }
    }
}
