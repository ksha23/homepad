import HomePadUI
import SwiftUI

/// First-run choice for weather: explains location use before iPadOS asks.
struct LocationSetupView: View {
    @Environment(PersonalWeatherService.self) private var weather
    let onChooseCity: () -> Void

    var body: some View {
        VStack(spacing: Theme.Spacing.l) {
            // A picture for the page, sized like an app icon rather than as text.
            Image(systemName: "cloud.sun.fill")
                .symbolRenderingMode(.multicolor)
                .font(.system(size: Theme.Size.appIcon))
            Text("Where Should Weather Be For?")
                .font(.largeTitle.bold())
            Text("Use this iPad's location for local weather, or pick a city. Your location is used only to fetch the forecast.")
                .font(.title3)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 560)
            HStack(spacing: Theme.Spacing.m) {
                GlassCapsuleButton("Use My Location", systemImage: "location.fill", isProminent: true) {
                    Task { await weather.useCurrentLocation() }
                }
                GlassCapsuleButton("Choose a City", systemImage: "magnifyingglass", action: onChooseCity)
            }
        }
        .foregroundStyle(.white)
        .padding(Theme.Spacing.xl)
    }
}
