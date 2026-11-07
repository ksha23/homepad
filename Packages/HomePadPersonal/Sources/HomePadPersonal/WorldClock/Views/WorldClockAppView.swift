import HomePadCore
import HomePadUI
import SwiftUI

/// The World Clock app: a grid of cities in the household's chosen clock style.
/// Long-press a city to remove it.
struct WorldClockAppView: View {
    @Environment(WorldClockStore.self) private var clocks
    @State private var isAdding = false

    var body: some View {
        AppScreen("World Clock", accessory: {
            GlassIconButton("plus", label: "Add City", isProminent: true) { isAdding = true }
        }, titleAccessory: { stylePicker }) {
            GeometryReader { proxy in
                let grid = Self.grid(count: clocks.cities.count + 1, in: proxy.size)
                // Analog clocks have a ticking second hand. The digital style shows minutes only.
                ClockTimeline(every: clocks.style == .digital ? .minute : .second) { now in
                    ScrollView {
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: Theme.Spacing.l), count: grid.columns),
                                  spacing: Theme.Spacing.l) {
                            CityClockCard(city: homeCity, style: clocks.style, date: now, isHome: true, clockSize: grid.clock)
                            ForEach(clocks.cities) { city in
                                CityClockCard(city: city, style: clocks.style, date: now, clockSize: grid.clock)
                                    .contextMenu {
                                        Button("Remove", systemImage: "trash", role: .destructive) { clocks.remove(city) }
                                    }
                            }
                        }
                        .padding(.bottom, Theme.Spacing.xl)
                    }
                    .scrollIndicators(.hidden)
                }
            }
        }
        .sheet(isPresented: $isAdding) {
            AddCitySheet()
        }
    }

    /// The clock style next to the title, as a menu clear of the Now Playing pill.
    private var stylePicker: some View {
        @Bindable var clocks = clocks
        return HeaderPicker("Style", selection: $clocks.style, title: clocks.style.title, systemImage: clocks.style.systemImage) {
            ForEach(WorldClockStyle.allCases, id: \.self) { Label($0.title, systemImage: $0.systemImage).tag($0) }
        }
    }

    /// Balanced columns (five cities as three and two, not four and one) and a
    /// clock size that fits two rows on screen. More cities scroll.
    static func grid(count: Int, in size: CGSize) -> (columns: Int, clock: CGFloat) {
        let isWide = size.width > size.height
        let columns: Int = switch count {
        case ...4: isWide ? max(count, 2) : 2
        case ...6: 3
        case ...8: 4
        default: isWide ? 5 : 3
        }
        let rows = CGFloat(min(Int((Double(count) / Double(columns)).rounded(.up)), 2))
        let cardWidth = (size.width - Theme.Spacing.l * CGFloat(columns - 1)) / CGFloat(columns)
        let cardHeight = (size.height - Theme.Spacing.l * (rows - 1) - Theme.Spacing.xl) / rows
        let clock = min(cardWidth - Theme.Spacing.l * 2, cardHeight - CityClockCard.labelsHeight - Theme.Spacing.l * 2 - Theme.Spacing.m)
        return (columns, max(clock, 120))
    }

    /// The iPad's own time zone, named after its city.
    private var homeCity: WorldClockCity {
        let zone = TimeZone.current
        let name = zone.identifier.split(separator: "/").last.map { $0.replacingOccurrences(of: "_", with: " ") } ?? "Home"
        return WorldClockCity(name: name, timeZoneID: zone.identifier)
    }
}
