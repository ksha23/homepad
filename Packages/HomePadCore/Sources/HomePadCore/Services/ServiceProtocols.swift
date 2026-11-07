import Foundation

// Service protocols are the only way modules talk to each other.
// A module implements one or more of these and installs it into `AppServices`
// from its `HomePadModule.register(services:registry:)`. Every protocol has a
// demo or no-op implementation in `DemoServices.swift` so each package builds,
// previews and runs on its own.
//
// Implementations should be `@Observable` classes so SwiftUI views that read
// their properties through these protocols update automatically.

@MainActor
public protocol SmartHomeService: AnyObject {
    var accessories: [HomeAccessory] { get }
    var scenes: [HomeScene] { get }
    var cameras: [HomeCamera] { get }
    /// Backends that are configured and connected right now.
    var connectedBackends: Set<SmartHomeBackend> { get }
    var favoriteAccessoryIDs: [HomeAccessory.ID] { get }

    func refresh() async
    func perform(_ command: AccessoryCommand, on accessoryID: HomeAccessory.ID) async throws
    func activateScene(_ sceneID: HomeScene.ID) async throws
    /// Latest still image for a camera, JPEG.
    func snapshot(cameraID: HomeCamera.ID) async throws -> Data?
    func setFavorite(_ accessoryID: HomeAccessory.ID, isFavorite: Bool)
    /// The ID this HomePad knows an accessory, scene or camera by, for an ID
    /// that may have been saved on another HomePad, such as a favorite or a
    /// face's tile picked there. HomeKit gives the same accessory a different
    /// identifier on every iPad. Returns `id` itself when it is this HomePad's
    /// own or nothing here matches it. Compare saved IDs through this, never
    /// with `==` against `accessories`.
    func localID(for id: String) -> String
    /// Raw backend call for power features, e.g. Home Assistant
    /// `callService(domain: "media_player", service: "join", data: [...])`.
    /// Backends without such a concept throw `SmartHomeError.unsupported`.
    func callService(domain: String, service: String, data: JSONValue) async throws
    /// Raw backend command that answers with data. For Home Assistant, `type` is a
    /// WebSocket command such as `config_entries/get`, `data` holds its top-level
    /// fields, and the return value is the command's `result`. Typed helpers for the
    /// common commands are in `SmartHomeCommands.swift`. Backends without such a
    /// concept throw `SmartHomeError.unsupported`.
    func sendCommand(_ type: String, data: JSONValue) async throws -> JSONValue

    /// Phones, tablets and other devices whose location the backend reports, for
    /// Find My. They update live with the backend's own state changes. Locations
    /// are personal: show them only through the Personal module's Find My rules.
    var trackedDevices: [TrackedDevice] { get }
    /// Named areas such as Home and Work that `TrackedDevice.place` refers to.
    var zones: [HomeZone] { get }
    /// Plays a sound on a tracked device so someone can find it: iCloud's Play
    /// Sound, or a critical notification through the Companion app. Throws a
    /// `SmartHomeError` that says why when it cannot be sent. Needs a recognized member.
    func playSound(onTrackedDevice id: TrackedDevice.ID) async throws
}

public extension SmartHomeService {
    func callService(domain: String, service: String, data: JSONValue) async throws {
        throw SmartHomeError.unsupported("\(domain).\(service)")
    }

    func sendCommand(_ type: String, data: JSONValue) async throws -> JSONValue {
        throw SmartHomeError.unsupported(type)
    }

    var trackedDevices: [TrackedDevice] { [] }

    var zones: [HomeZone] { [] }

    func playSound(onTrackedDevice id: TrackedDevice.ID) async throws {
        throw SmartHomeError.unsupported("Playing a sound")
    }

    func localID(for id: String) -> String { id }

    /// Saved IDs as this HomePad knows them, in order and each once.
    func localIDs(for ids: [String]) -> [String] {
        var seen = Set<String>()
        return ids.map { localID(for: $0) }.filter { seen.insert($0).inserted }
    }

    var rooms: [String] {
        Array(Set(accessories.compactMap(\.room))).sorted()
    }

    var favorites: [HomeAccessory] {
        localIDs(for: favoriteAccessoryIDs).compactMap { id in accessories.first { $0.id == id } }
    }

    /// The accessory a saved ID names, here or on another HomePad.
    func accessory(_ id: HomeAccessory.ID) -> HomeAccessory? {
        let id = localID(for: id)
        return accessories.first { $0.id == id }
    }

    /// Fuzzy lookup by name and optional room, for the assistant ("kitchen lights").
    func findAccessories(matching query: String, room: String? = nil) -> [HomeAccessory] {
        let needle = query.lowercased()
        return accessories.filter { accessory in
            let nameMatch = accessory.name.lowercased().contains(needle)
                || needle.contains(accessory.name.lowercased())
                || accessory.kind.rawValue.lowercased() == needle
            let roomMatch = room.map { accessory.room?.lowercased().contains($0.lowercased()) ?? false } ?? true
            return nameMatch && roomMatch
        }
    }
}

@MainActor
public protocol MediaService: AnyObject {
    var nowPlaying: NowPlaying? { get }
    var outputs: [AudioOutput] { get }
    /// Name of the current system audio route, e.g. "Living Room" for an AirPlay group.
    var currentRouteName: String { get }

    func play() async
    func pause() async
    func nextTrack() async
    func previousTrack() async
    func setVolume(_ volume: Double) async
    /// The level `setVolume` sets when it is not this iPad's, such as the AirPlay
    /// speakers Apple's player plays to. Nil means this iPad's own volume.
    var speakerVolume: Double? { get }
    /// The current volume level, from 0 to 1.
    var currentVolume: Double { get }
    /// Search and play, e.g. "jazz for cooking". Returns what started playing.
    func playSearch(_ query: String) async throws -> String
    /// Play on a specific output (Home Assistant players can be targeted directly;
    /// AirPlay outputs fall back to showing the system route picker).
    func select(outputID: AudioOutput.ID) async throws
    /// Lowers this iPad's music for a spoken request, as a HomePod lowers it for
    /// Siri, remembering that it did.
    func duckForVoice()
    /// Brings back the volume `duckForVoice` lowered.
    func restoreAfterVoice() async
}

public extension MediaService {
    var speakerVolume: Double? { nil }
    var currentVolume: Double { speakerVolume ?? 0.5 }
    func duckForVoice() {}
    func restoreAfterVoice() async {}
}

@MainActor
public protocol AssistantService: AnyObject {
    var phase: AssistantPhase { get }
    /// Live partial transcript while listening.
    var liveTranscript: String { get }
    /// Display name of the provider that will answer, e.g. "Claude" or "Apple Intelligence".
    var activeProviderName: String { get }
    /// True when at least one provider can answer (a key is set or the on-device model is available).
    var isConfigured: Bool { get }

    func ask(_ request: AssistantRequest) -> AsyncThrowingStream<AssistantEvent, Error>
    /// Start listening for one spoken request (push-to-talk, wake word or swipe down).
    func startListening()
    func stopListening()
    /// Stop speaking and cancel the current answer.
    func cancel()
    /// Cancels everything and hides the assistant.
    func dismiss()
}

public extension AssistantService {
    func dismiss() { cancel() }
}

@MainActor
public protocol TimerService: AnyObject {
    var timers: [HomeTimer] { get }

    @discardableResult
    func start(duration: TimeInterval, label: String) -> HomeTimer
    func pause(_ id: HomeTimer.ID)
    func resume(_ id: HomeTimer.ID)
    func cancel(_ id: HomeTimer.ID)
    func add(_ seconds: TimeInterval, to id: HomeTimer.ID)
}

@MainActor
public protocol PresenceService: AnyObject {
    var snapshot: PresenceSnapshot { get }
    var isRunning: Bool { get }
    /// True while a camera is actually looking for people. False while presence
    /// runs without one: another feature holds the camera (Mirror, Camera Lab,
    /// enrollment), the camera setting is off, permission is missing, or only
    /// the microphone listens. Only then does "nobody present" mean nobody is there.
    var isCameraSensing: Bool { get }
    /// True when the device has a TrueDepth (Face ID) camera.
    var hasTrueDepth: Bool { get }

    func start()
    func stop()
}

public extension PresenceService {
    var isCameraSensing: Bool { isRunning }
}

@MainActor
public protocol CalendarService: AnyObject {
    var hasAccess: Bool { get }
    func requestAccess() async -> Bool
    func events(from start: Date, to end: Date) async -> [CalendarItem]
    func reminders(includeCompleted: Bool) async -> [CalendarItem]
    func addReminder(title: String, due: Date?, listName: String?) async throws
    func addEvent(title: String, start: Date, end: Date) async throws
    /// Adds an event with its place, all day or not, to the calendar it names,
    /// which must be one of `writableEventCalendars()`. A nil calendar picks
    /// the best one for the current viewer.
    func addEvent(_ draft: EventDraft) async throws
    /// Calendars the current viewer may add events to, the one new events go
    /// to by default first.
    func writableEventCalendars() async -> [EventCalendarInfo]
    /// Lists the current viewer may see.
    func reminderLists() async -> [ReminderListInfo]
    func setReminderCompleted(id: String, completed: Bool) async throws
    func removeReminder(id: String) async throws
    /// Changes whenever calendars, access or who may see them change, so a
    /// view that keeps events (a face) reloads when a calendar is added.
    var reloadKey: String { get }
    /// How many events between two dates are left out because they belong to
    /// someone who is not recognized right now, so faces can say so.
    func hiddenEventCount(from start: Date, to end: Date) async -> Int
}

/// Thrown by services that do not support an optional capability.
public struct UnsupportedOperation: LocalizedError, Sendable {
    public let operation: String
    public init(_ operation: String) { self.operation = operation }
    public var errorDescription: String? { "\(operation) is not supported here." }
}

public extension CalendarService {
    /// A service without calendars to choose from can still add a plain event.
    /// Anything it would have to drop (a place, all day, a calendar) is refused
    /// rather than lost.
    func addEvent(_ draft: EventDraft) async throws {
        guard draft.location == nil, !draft.isAllDay, draft.calendarID == nil else {
            throw UnsupportedOperation("Adding an event with a place, all day or to a chosen calendar")
        }
        try await addEvent(title: draft.title, start: draft.start, end: draft.end)
    }
    func writableEventCalendars() async -> [EventCalendarInfo] { [] }
    func reminderLists() async -> [ReminderListInfo] { [] }
    func setReminderCompleted(id: String, completed: Bool) async throws { throw UnsupportedOperation("Completing reminders") }
    func removeReminder(id: String) async throws { throw UnsupportedOperation("Removing reminders") }
    var reloadKey: String { "" }
    func hiddenEventCount(from start: Date, to end: Date) async -> Int { 0 }
}

@MainActor
public protocol WeatherService: AnyObject {
    var current: WeatherSnapshot? { get }
    func refresh() async
    /// The weather at a named place instead of the household's own, in the
    /// household's units. Services cache it, so asking again soon is cheap.
    /// Nil when it cannot be had.
    func snapshot(for location: WeatherLocation) async -> WeatherSnapshot?
}

public extension WeatherService {
    func snapshot(for location: WeatherLocation) async -> WeatherSnapshot? { nil }
}

@MainActor
public protocol IntercomService: AnyObject {
    /// Other HomePads and companion devices reachable on the network.
    var peers: [String] { get }
    /// Send a short spoken announcement (recorded audio) or text to everyone, or to one peer.
    func announce(text: String, audio: Data?, to peer: String?) async throws
}
