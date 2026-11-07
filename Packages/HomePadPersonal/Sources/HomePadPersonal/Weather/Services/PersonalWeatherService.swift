import Foundation
import HomePadCore
import Observation

/// HomePad's weather service. Installed into `services.weather`.
///
/// Tries WeatherKit first and falls back to Open-Meteo automatically, so
/// weather keeps working when WeatherKit provisioning is missing. The Personal
/// module's weather task refreshes it on a cadence from Settings
/// (`PersonalBackgroundTasks`), and it caches the last forecast on disk.
@MainActor
@Observable
public final class PersonalWeatherService: HomePadCore.WeatherService {
    public enum Status: Equatable {
        case idle
        case loading
        /// Nobody chose a location yet. The Weather app shows the location prompt.
        case needsLocation
        case failed(String)
    }

    /// Legally required credit for the source of the current forecast.
    public struct Attribution: Equatable {
        public var name: String
        public var url: URL?
    }

    public private(set) var forecast: WeatherForecast?
    public private(set) var status: Status = .idle
    public private(set) var attribution: Attribution?

    @ObservationIgnored private let settings: SettingsStore
    @ObservationIgnored private let cache = ForecastCache()
    @ObservationIgnored private let locator = LocationResolver()
    @ObservationIgnored private let log = Log.make("Weather")
    /// Forecasts for named places (`snapshot(for:)`), by coordinate.
    @ObservationIgnored private var placeForecasts: [String: WeatherForecast] = [:]
    @ObservationIgnored private var placeFetches: [String: Task<WeatherForecast?, Never>] = [:]

    /// Providers in order of preference. Tests and previews can replace them.
    @ObservationIgnored var providers: [any WeatherProvider] = [WeatherKitProvider(), OpenMeteoProvider()]

    public init(settings: SettingsStore) {
        self.settings = settings
        self.forecast = cache.load()
        updateAttribution()
    }

    // MARK: Core protocol

    /// Core snapshot in the household's units, for faces and other modules.
    public var current: WeatherSnapshot? {
        forecast.map(snapshot(from:))
    }

    /// The weather at a named place, such as a city a face shows. Each place
    /// is fetched at most once per refresh cadence (30 minutes by default),
    /// so faces and their thumbnails can ask whenever they appear. Demo data
    /// gives demo weather, and so does the simulator when every source fails.
    public func snapshot(for location: WeatherLocation) async -> WeatherSnapshot? {
        let key = Self.placeKey(location)
        let cadence = Double(max(10, settings[PersonalSettings.weatherRefreshMinutes])) * 60
        if let cached = placeForecasts[key], Date().timeIntervalSince(cached.fetchedAt) < cadence {
            return snapshot(from: cached)
        }
        // Views asking at the same time share one fetch.
        let task = placeFetches[key] ?? Task { await self.fetchForecast(for: location) }
        placeFetches[key] = task
        let fetched = await task.value
        placeFetches[key] = nil
        if let fetched { placeForecasts[key] = fetched }
        return placeForecasts[key].map(snapshot(from:))
    }

    /// A forecast as a Core snapshot in the household's units.
    private func snapshot(from forecast: WeatherForecast) -> WeatherSnapshot {
        let units = self.units
        let unit = units.temperatureUnit()
        let today = forecast.today
        return WeatherSnapshot(
            locationName: forecast.place.name,
            temperature: units.temperature(forecast.current.temperature),
            high: today.map { units.temperature($0.high) },
            low: today.map { units.temperature($0.low) },
            conditionText: forecast.current.condition.text,
            symbolName: forecast.current.condition.symbolName(isDaylight: forecast.current.isDaylight),
            unit: unit,
            hourly: forecast.upcomingHours(at: Date()).prefix(24).map {
                WeatherSnapshot.Hour(date: $0.date, temperature: units.temperature($0.temperature),
                                     symbolName: $0.condition.symbolName(isDaylight: $0.isDaylight))
            },
            daily: forecast.daily.map {
                WeatherSnapshot.Day(date: $0.date, high: units.temperature($0.high), low: units.temperature($0.low),
                                    symbolName: $0.condition.symbolName(isDaylight: true),
                                    precipitationChance: $0.precipitationChance)
            },
            updatedAt: forecast.fetchedAt,
            sunrise: today?.sunrise,
            sunset: today?.sunset,
            isDaylight: forecast.current.isDaylight
        )
    }

    private func fetchForecast(for location: WeatherLocation) async -> WeatherForecast? {
        let place = WeatherPlace(name: location.name, latitude: location.latitude, longitude: location.longitude,
                                 timeZoneID: location.timeZoneID)
        if settings[PersonalSettings.demoData] { return DemoWeatherProvider.forecast(for: place) }
        for provider in providers {
            do {
                return try await provider.forecast(for: place)
            } catch {
                log.notice("\(provider.source.rawValue, privacy: .public) failed for a place, trying the next source: \(error.localizedDescription, privacy: .public)")
            }
        }
        #if targetEnvironment(simulator)
        return DemoWeatherProvider.forecast(for: place)
        #else
        return nil
        #endif
    }

    private static func placeKey(_ location: WeatherLocation) -> String {
        String(format: "%.3f,%.3f", location.latitude, location.longitude)
    }

    public func refresh() async {
        guard let place = await resolvePlace() else { return }
        status = .loading
        var lastError: Error?
        for provider in providers {
            do {
                let result = try await provider.forecast(for: place)
                apply(result)
                return
            } catch {
                lastError = error
                log.notice("\(provider.source.rawValue, privacy: .public) failed, trying the next source: \(error.localizedDescription, privacy: .public)")
            }
        }
        status = .failed(lastError?.localizedDescription ?? "Weather is unavailable right now.")
    }

    // MARK: Settings

    public var units: WeatherUnitSystem { settings[PersonalSettings.weatherUnits] }
    public var locationChoice: WeatherLocationChoice { settings[PersonalSettings.weatherLocation] }

    /// Uses the iPad's location. Asks for permission now if needed.
    public func useCurrentLocation() async {
        settings[PersonalSettings.weatherLocation] = .current
        forecast = nil
        await refresh()
    }

    /// Uses a city chosen by search.
    public func choose(_ place: WeatherPlace) async {
        settings[PersonalSettings.weatherLocation] = .place(place)
        forecast = nil
        await refresh()
    }

    /// Refreshes when the forecast is older than the refresh cadence. Screens
    /// that show weather call it as they appear.
    public func refreshIfStale() async {
        if isStale { await refresh() }
    }

    /// Seconds between scheduled refreshes: the Settings choice, at least ten minutes.
    var refreshInterval: TimeInterval {
        Double(max(10, settings[PersonalSettings.weatherRefreshMinutes])) * 60
    }

    /// A scheduled refresh, for the weather background task.
    func scheduledRefresh() async -> BackgroundTaskOutcome {
        await refresh()
        switch status {
        case .failed(let reason):
            return .failed(reason)
        case .needsLocation:
            return .skipped("No place for weather has been chosen yet.")
        case .idle, .loading:
            guard let forecast else { return .skipped("No forecast yet.") }
            return .done("Forecast for \(forecast.place.name) from \(attribution?.name ?? "the weather service").")
        }
    }

    /// True when the forecast is older than the refresh cadence.
    public var isStale: Bool {
        guard let forecast else { return true }
        let cadence = Double(settings[PersonalSettings.weatherRefreshMinutes]) * 60
        return Date().timeIntervalSince(forecast.fetchedAt) > cadence
    }

    // MARK: Private

    private func resolvePlace() async -> WeatherPlace? {
        switch locationChoice {
        case .undecided:
            if settings[PersonalSettings.demoData] {
                apply(DemoWeatherProvider.forecast(for: WeatherPlace(name: "Madison", latitude: 43.07, longitude: -89.40, timeZoneID: "America/Chicago")))
            } else {
                status = .needsLocation
            }
            return nil
        case .place(let place):
            return place
        case .current:
            do {
                return try await locator.currentPlace()
            } catch {
                status = .failed(error.localizedDescription)
                return nil
            }
        }
    }

    private func apply(_ result: WeatherForecast) {
        forecast = result
        status = .idle
        if result.source != .demo { cache.save(result) }
        updateAttribution()
    }

    private func updateAttribution() {
        switch forecast?.source {
        case .weatherKit:
            attribution = Attribution(name: "Weather", url: nil)
            Task { [weak self] in
                guard let credit = await WeatherKitProvider.attribution() else { return }
                self?.attribution = Attribution(name: credit.name, url: credit.legalURL)
            }
        case .openMeteo:
            attribution = Attribution(name: "Weather data by Open-Meteo.com", url: URL(string: "https://open-meteo.com/"))
        case .demo:
            attribution = Attribution(name: "Demo weather", url: nil)
        case nil:
            attribution = nil
        }
    }
}
