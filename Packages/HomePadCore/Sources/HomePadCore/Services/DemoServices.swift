import Foundation
import Observation

// Demo and no-op implementations of every service protocol.
// `AppServices` starts with these, and modules replace them in `register`.
// The demo smart home gives faces, the Home app and the assistant realistic
// data in the simulator before any real backend is configured.

@MainActor
@Observable
public final class DemoSmartHomeService: SmartHomeService {
    public var accessories: [HomeAccessory]
    public var scenes: [HomeScene]
    public var cameras: [HomeCamera]
    public var connectedBackends: Set<SmartHomeBackend> = [.demo]
    public var favoriteAccessoryIDs: [HomeAccessory.ID]

    public init() {
        accessories = [
            HomeAccessory(id: "demo:light.kitchen", name: "Kitchen Lights", room: "Kitchen", kind: .light, backend: .demo,
                          capabilities: [.power, .brightness, .colorTemperature], state: AccessoryState(isOn: true, brightness: 0.7)),
            HomeAccessory(id: "demo:light.living", name: "Living Room Lamp", room: "Living Room", kind: .light, backend: .demo,
                          capabilities: [.power, .brightness], state: AccessoryState(isOn: false, brightness: 0.4)),
            HomeAccessory(id: "demo:light.entry", name: "Entryway Lights", room: "Entryway", kind: .light, backend: .demo,
                          capabilities: [.power], state: AccessoryState(isOn: true)),
            HomeAccessory(id: "demo:climate.living", name: "Thermostat", room: "Living Room", kind: .thermostat, backend: .demo,
                          capabilities: [.targetTemperature, .hvacMode],
                          state: AccessoryState(currentTemperature: 71, targetTemperature: 70, temperatureUnit: .fahrenheit, hvacMode: .cool, humidity: 41)),
            HomeAccessory(id: "demo:lock.front", name: "Front Door", room: "Entryway", kind: .lock, backend: .demo,
                          capabilities: [.lock], state: AccessoryState(lockState: .locked)),
            HomeAccessory(id: "demo:cover.living", name: "Shades", room: "Living Room", kind: .cover, backend: .demo,
                          capabilities: [.position], state: AccessoryState(position: 0)),
            HomeAccessory(id: "demo:fan.office", name: "Ceiling Fan", room: "Office", kind: .fan, backend: .demo,
                          capabilities: [.power], state: AccessoryState(isOn: false)),
            HomeAccessory(id: "demo:sensor.office_temp", name: "Office Temperature", room: "Office", kind: .sensor, backend: .demo,
                          state: AccessoryState(sensorValue: 72.4, sensorUnit: "°")),
        ]
        scenes = [
            HomeScene(id: "demo:scene.morning", name: "Good Morning", backend: .demo, systemImage: "sun.horizon.fill"),
            HomeScene(id: "demo:scene.night", name: "Good Night", backend: .demo, systemImage: "moon.stars.fill"),
            HomeScene(id: "demo:scene.away", name: "Leave Home", backend: .demo, systemImage: "figure.walk.departure"),
        ]
        cameras = [
            HomeCamera(id: "demo:camera.front", name: "Front Door", room: "Entryway", backend: .demo, isDoorbell: true),
            HomeCamera(id: "demo:camera.yard", name: "Back Yard", room: "Outside", backend: .demo),
        ]
        favoriteAccessoryIDs = ["demo:climate.living", "demo:light.kitchen", "demo:lock.front", "demo:light.entry", "demo:fan.office", "demo:cover.living"]
    }

    public func refresh() async {}

    public func perform(_ command: AccessoryCommand, on accessoryID: HomeAccessory.ID) async throws {
        guard let index = accessories.firstIndex(where: { $0.id == accessoryID }) else {
            throw SmartHomeError.accessoryNotFound(accessoryID)
        }
        var state = accessories[index].state
        switch command {
        case .setPower(let on): state.isOn = on
        case .toggle: state.isOn = !(state.isOn ?? false)
        case .setBrightness(let value): state.brightness = value; state.isOn = value > 0
        case .setColorTemperature(let kelvin): state.colorTemperatureKelvin = kelvin
        case .setHueSaturation(let hue, let saturation): state.hue = hue; state.saturation = saturation
        case .setTargetTemperature(let value): state.targetTemperature = value
        case .setHVACMode(let mode): state.hvacMode = mode
        case .lock: state.lockState = .locked
        case .unlock: state.lockState = .unlocked
        case .setPosition(let value): state.position = value
        case .open: state.position = 1
        case .close: state.position = 0
        case .stop: break
        case .setVolume(let value): state.volume = value
        case .play: state.isPlaying = true; state.isActive = true
        case .pause: state.isPlaying = false; state.isActive = false
        case .nextTrack, .previousTrack: break
        }
        accessories[index].state = state
    }

    public func activateScene(_ sceneID: HomeScene.ID) async throws {}

    public func snapshot(cameraID: HomeCamera.ID) async throws -> Data? { nil }

    public func setFavorite(_ accessoryID: HomeAccessory.ID, isFavorite: Bool) {
        favoriteAccessoryIDs.removeAll { $0 == accessoryID }
        if isFavorite { favoriteAccessoryIDs.append(accessoryID) }
    }
}

@MainActor
@Observable
public final class NoopMediaService: MediaService {
    public var nowPlaying: NowPlaying?
    public var outputs: [AudioOutput] = [AudioOutput(id: "builtin", name: "iPad", kind: .builtInSpeaker, isActive: true)]
    public var currentRouteName = "iPad"

    public init() {}
    public func play() async { nowPlaying?.isPlaying = true }
    public func pause() async { nowPlaying?.isPlaying = false }
    public func nextTrack() async {}
    public func previousTrack() async {}
    public func setVolume(_ volume: Double) async {}
    public func playSearch(_ query: String) async throws -> String {
        nowPlaying = NowPlaying(title: query.capitalized, artist: "Demo", isPlaying: true, source: .system, outputName: currentRouteName)
        return query
    }
    public func select(outputID: AudioOutput.ID) async throws {}
}

@MainActor
@Observable
public final class NoopAssistantService: AssistantService {
    public var phase: AssistantPhase = .idle
    public var liveTranscript = ""
    public var activeProviderName = "None"
    public var isConfigured = false

    public init() {}

    public func ask(_ request: AssistantRequest) -> AsyncThrowingStream<AssistantEvent, Error> {
        AsyncThrowingStream { continuation in
            continuation.yield(.finished(fullText: "No assistant is configured yet. Add an AI provider in Settings."))
            continuation.finish()
        }
    }

    public func startListening() { phase = .listening }
    public func stopListening() { phase = .idle }
    public func cancel() { phase = .idle }
}

/// A simple in-memory timer service. The Kitchen module replaces it with one
/// that adds Live Activities, alarms and persistence.
@MainActor
@Observable
public final class InMemoryTimerService: TimerService {
    public var timers: [HomeTimer] = []
    private let events: EventBus?
    private var tickTask: Task<Void, Never>?

    public init(events: EventBus? = nil) {
        self.events = events
    }

    @discardableResult
    public func start(duration: TimeInterval, label: String) -> HomeTimer {
        let timer = HomeTimer(label: label, duration: duration)
        timers.append(timer)
        ensureTicking()
        return timer
    }

    public func pause(_ id: HomeTimer.ID) {
        guard let i = timers.firstIndex(where: { $0.id == id }), timers[i].status == .running else { return }
        timers[i].remainingWhenPaused = timers[i].remaining()
        timers[i].status = .paused
        timers[i].endDate = nil
    }

    public func resume(_ id: HomeTimer.ID) {
        guard let i = timers.firstIndex(where: { $0.id == id }), timers[i].status == .paused else { return }
        timers[i].endDate = Date().addingTimeInterval(timers[i].remainingWhenPaused ?? 0)
        timers[i].status = .running
        timers[i].remainingWhenPaused = nil
        ensureTicking()
    }

    public func cancel(_ id: HomeTimer.ID) {
        timers.removeAll { $0.id == id }
    }

    public func add(_ seconds: TimeInterval, to id: HomeTimer.ID) {
        guard let i = timers.firstIndex(where: { $0.id == id }) else { return }
        switch timers[i].status {
        case .running: timers[i].endDate = timers[i].endDate?.addingTimeInterval(seconds)
        case .paused: timers[i].remainingWhenPaused = (timers[i].remainingWhenPaused ?? 0) + seconds
        case .finished:
            timers[i].status = .running
            timers[i].endDate = Date().addingTimeInterval(seconds)
            ensureTicking()
        }
        timers[i].duration += seconds
    }

    private func ensureTicking() {
        guard tickTask == nil else { return }
        tickTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(500))
                guard let self else { return }
                let now = Date()
                for i in self.timers.indices where self.timers[i].status == .running && self.timers[i].remaining(at: now) <= 0 {
                    self.timers[i].status = .finished
                    self.events?.post(.timerFinished(id: self.timers[i].id, label: self.timers[i].label))
                }
                if !self.timers.contains(where: { $0.status == .running }) {
                    self.tickTask = nil
                    return
                }
            }
        }
    }
}

@MainActor
@Observable
public final class NoopPresenceService: PresenceService {
    public var snapshot = PresenceSnapshot.empty
    public var isRunning = false
    public var hasTrueDepth = false
    public init() {}
    public func start() { isRunning = true }
    public func stop() { isRunning = false }
}

@MainActor
@Observable
public final class DemoCalendarService: CalendarService {
    public var hasAccess = true
    public init() {}
    public func requestAccess() async -> Bool { true }
    public func events(from start: Date, to end: Date) async -> [CalendarItem] {
        let today = Calendar.current.startOfDay(for: Date())
        return [
            CalendarItem(id: "demo1", title: "Standup", start: today.addingTimeInterval(9 * 3600), end: today.addingTimeInterval(9.5 * 3600)),
            CalendarItem(id: "demo2", title: "Pick up groceries", start: today.addingTimeInterval(17 * 3600), end: today.addingTimeInterval(18 * 3600)),
            CalendarItem(id: "demo3", title: "Dinner with friends", start: today.addingTimeInterval(19.5 * 3600), end: today.addingTimeInterval(21 * 3600)),
        ].filter { $0.end >= start && $0.start <= end }
    }
    public func reminders(includeCompleted: Bool) async -> [CalendarItem] { [] }
    public func addReminder(title: String, due: Date?, listName: String?) async throws {}
    public func addEvent(title: String, start: Date, end: Date) async throws {}
}

@MainActor
@Observable
public final class DemoWeatherService: WeatherService {
    public var current: WeatherSnapshot? = WeatherSnapshot(
        locationName: "Madison", temperature: 54, high: 57, low: 49,
        conditionText: "Partly Cloudy", symbolName: "cloud.sun.fill", unit: .fahrenheit
    )
    public init() {}
    public func refresh() async {}

    /// The demo weather under the place's name, a little cooler the farther it is from the equator.
    public func snapshot(for location: WeatherLocation) async -> WeatherSnapshot? {
        guard var snapshot = current else { return nil }
        let shift = (35 - abs(location.latitude)) * 0.6
        snapshot.locationName = location.name
        snapshot.temperature = (snapshot.temperature + shift).rounded()
        snapshot.high = snapshot.high.map { ($0 + shift).rounded() }
        snapshot.low = snapshot.low.map { ($0 + shift).rounded() }
        return snapshot
    }
}

@MainActor
@Observable
public final class NoopIntercomService: IntercomService {
    public var peers: [String] = []
    public init() {}
    public func announce(text: String, audio: Data?, to peer: String?) async throws {}
}
