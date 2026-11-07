import HomePadCore
import HomePadUI
import SwiftUI

/// The Weather app. Glanceable from across the room (city, temperature,
/// conditions) and detailed up close (hourly, 10-day, details), switching
/// with `ProximityAdaptive` like HomeView's distance-aware Weather. The sky
/// fills the screen behind the standard header.
struct WeatherAppView: View {
    @Environment(PersonalWeatherService.self) private var weather
    @State private var isPickingPlace = false

    var body: some View {
        AppScreen("Weather", accessory: {
            if weather.forecast != nil {
                GlassIconButton("list.bullet", label: "Choose Location") { isPickingPlace = true }
            }
        }) {
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .foregroundStyle(.white)
        .background {
            WeatherSkyBackground(condition: weather.forecast?.current.condition ?? .partlyCloudy,
                                 isDaylight: weather.forecast?.current.isDaylight ?? true)
                .overlay(alignment: .top) { headerShade }
        }
        // The sky is a picture, so the screen looks the same in Light and Dark,
        // like Apple's Weather: white text, and glass dark enough to carry it.
        // The place picker below is a sheet and follows the appearance.
        .environment(\.colorScheme, .dark)
        .nightModeAware()
        .task { await weather.refreshIfStale() }
        .sheet(isPresented: $isPickingPlace) {
            PlacePickerSheet()
        }
    }

    /// A light shade at the top, so the title and the glass buttons read over
    /// a white cloud.
    private var headerShade: some View {
        LinearGradient(colors: [.black.opacity(0.25), .clear], startPoint: .top, endPoint: .bottom)
            .frame(height: 260)
            .ignoresSafeArea()
            .allowsHitTesting(false)
    }

    @ViewBuilder
    private var content: some View {
        if let forecast = weather.forecast {
            ProximityAdaptive {
                WeatherFarView(forecast: forecast, units: weather.units)
            } near: {
                WeatherNearView(forecast: forecast, units: weather.units)
            }
        } else {
            switch weather.status {
            case .needsLocation:
                LocationSetupView(onChooseCity: { isPickingPlace = true })
            case .failed(let message):
                EmptyStateView("Weather Unavailable", message: message, systemImage: "cloud.slash", actionTitle: "Try Again") {
                    Task { await weather.refresh() }
                }
            case .idle, .loading:
                ProgressView().controlSize(.large).tint(.white)
            }
        }
    }
}
