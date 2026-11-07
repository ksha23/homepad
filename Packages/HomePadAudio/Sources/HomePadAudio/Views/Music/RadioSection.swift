import HomePadUI
import SwiftUI

/// Internet radio: favorites, HomePad's picks, recently played, Radio Browser
/// search and adding a stream by URL. Works without any account.
struct RadioSection: View {
    @Environment(AudioMediaService.self) private var media
    @State private var query = ""
    @State private var showsAddStation = false

    var body: some View {
        let library = media.radioLibrary
        VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
            HStack(spacing: Theme.Spacing.m) {
                TextField("Search thousands of stations", text: $query)
                    .textFieldStyle(.plain)
                    .font(.title3)
                    .padding(Theme.Spacing.m)
                    .glassEffect(.regular, in: .capsule)
                    .frame(maxWidth: 640)
                    .submitLabel(.search)
                    .onSubmit { Task { await library.search(query) } }
                GlassCapsuleButton("Add Station", systemImage: "plus") { showsAddStation = true }
            }
            if !query.isEmpty, library.isSearching || !library.searchResults.isEmpty || library.searchError != nil {
                searchResults(library)
            }
            if !library.favorites.isEmpty {
                stationRow("Favorites", library.favorites)
            }
            stationRow("HomePad Picks", library.curated)
            if !library.recents.isEmpty {
                stationRow("Recently Played", library.recents)
            }
            Text("Station search by Radio Browser, a free community directory.")
                .font(.footnote)
                .foregroundStyle(.tertiary)
        }
        .sheet(isPresented: $showsAddStation) { AddStationSheet().environment(media) }
    }

    private func searchResults(_ library: RadioLibrary) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            SectionHeader("Results")
            if library.isSearching {
                ProgressView()
            } else if let error = library.searchError {
                Text(error).foregroundStyle(.secondary)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(alignment: .top, spacing: Theme.Spacing.l) {
                        ForEach(library.searchResults) { tile($0) }
                    }
                }
            }
        }
    }

    private func stationRow(_ title: String, _ stations: [RadioStation]) -> some View {
        ShelfRow(title) {
            ForEach(stations) { tile($0) }
        }
    }

    private func tile(_ station: RadioStation) -> some View {
        let library = media.radioLibrary
        let isCurrent = media.activeKind == .radio && media.radio.station?.id == station.id
        return ArtworkTile(title: station.name, subtitle: station.subtitle, artworkURL: station.artworkURL,
                           systemImage: "dot.radiowaves.left.and.right", isActive: isCurrent) {
            Task { await media.perform { try await media.play(station: station) } }
        }
        .contextMenu {
            Button(library.isFavorite(station) ? "Remove from Favorites" : "Add to Favorites",
                   systemImage: library.isFavorite(station) ? "star.slash" : "star") {
                library.toggleFavorite(station)
            }
            ForEach(media.outputs.filter { $0.kind == .homeAssistantPlayer }) { speaker in
                Button("Play on \(speaker.name)", systemImage: "hifispeaker") {
                    Task { await media.perform { try await media.play(station: station, on: speaker.id) } }
                }
            }
        }
    }
}

/// Adds a stream URL as a favorite station.
struct AddStationSheet: View {
    @Environment(AudioMediaService.self) private var media
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var url = ""
    @State private var error: String?

    var body: some View {
        SheetScreen("Add Station") {
            GlassCapsuleButton("Add", isProminent: true, action: add)
                .disabled(url.isEmpty)
        } content: {
            Form {
                Section {
                    TextField("Name", text: $name)
                    TextField("Stream URL", text: $url)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                } footer: {
                    Text(error ?? "Use a direct stream link, or a .pls or .m3u playlist link.")
                        .foregroundStyle(error == nil ? Color.secondary : Color.orange)
                }
            }
        }
    }

    private func add() {
        do {
            try media.radioLibrary.addCustom(name: name, urlString: url)
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }
}
