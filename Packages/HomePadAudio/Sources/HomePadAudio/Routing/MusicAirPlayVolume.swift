import Foundation
import HomePadCore
import Observation
import ObjectiveC

/// The volume of the AirPlay speakers Apple Music plays to.
///
/// Apple Music's player keeps its own long-form AirPlay route. The public
/// slider (MPVolumeView) and the volume buttons follow HomePad's own session,
/// which stays on the iPad speaker to keep the microphone, so they never reach
/// the HomePods. AVFoundation's private `AVOutputContext` has a shared context
/// for that long-form route (`sharedAudioPresentationOutputContext`): on the
/// iPad it names the speakers ("Back Stereo Pair"), reads their volume and
/// reports `canSetVolume`. With several speakers it is the group's volume, as
/// the AirPlay menu's top slider. Every call is checked with `responds(to:)` and
/// runs inside `catchingObjCException`, since the class is private.
///
/// It reads twice a second for the app's life, so the name and the level follow
/// speakers picked and volumes changed elsewhere (three property reads).
///
/// The last level the person chose is remembered for each set of speakers
/// (`MusicVolumeMemory`), and each reading goes through `MusicVolumeRestore`,
/// which says what to show and when to put that level back.
///
/// A second reader follows the system route (`Route.system`), where apps that
/// do not play long-form audio send their sound, the Spotify app among them.
/// It keeps no memory and restores nothing.
@MainActor
@Observable
final class MusicAirPlayVolume {
    /// Which of AVFoundation's shared output contexts this reads.
    enum Route {
        /// Long-form audio (AirPlay 2): Apple's music player and apps that adopted it.
        case longForm
        /// The system route, which every other app's sound follows. Spotify on
        /// iOS has not adopted long-form audio, so its AirPlay goes here.
        case system

        var contextSelector: String {
            switch self {
            case .longForm: "sharedAudioPresentationOutputContext"
            case .system: "sharedSystemAudioContext"
            }
        }
    }

    /// The speakers the music plays to ("Back Stereo Pair", "Living Room and
    /// Kitchen", "iPad"), nil without the context.
    private(set) var speakerName: String?
    private(set) var volume: Float = 0
    private(set) var canSetVolume = false
    /// The level remembered for these speakers, or for the speakers used last,
    /// shown while the speakers cannot be read.
    private(set) var rememberedLevel: Double?

    /// Receives a line for each reading that changed and each volume sent.
    @ObservationIgnored var onLog: ((String) -> Void)?
    /// True while Apple's player plays. Set by the media service.
    @ObservationIgnored var isMusicPlaying: () -> Bool = { false }

    @ObservationIgnored private let context: NSObject?
    @ObservationIgnored private let settings: SettingsStore?
    @ObservationIgnored private var restore: MusicVolumeRestore
    @ObservationIgnored private var pollTask: Task<Void, Never>?
    @ObservationIgnored private var saveTask: Task<Void, Never>?
    /// Readings are ignored until then, so one taken before a set lands does not pull the slider back.
    @ObservationIgnored private var holdReadingsUntil = Date.distantPast
    @ObservationIgnored private var pending: Float?
    /// When `pending` was chosen. A level that could not be sent at once is sent
    /// once the speakers can take it, if that is within `pendingLifetime`.
    @ObservationIgnored private var pendingSince = Date.distantPast
    @ObservationIgnored private var sendTask: Task<Void, Never>?
    @ObservationIgnored private var lastSent = Date.distantPast
    @ObservationIgnored private var lastReading = ""

    /// Shortest gap between two volumes sent while a finger drags the slider.
    private let sendInterval: TimeInterval = 0.08
    private let pendingLifetime: TimeInterval = 10

    /// Reads nothing until `startUpdating()`, so the first reading reaches `onLog`.
    /// - Parameters:
    ///   - settings: Where the remembered levels are kept. Nil keeps none.
    ///   - route: The output context to read.
    init(settings: SettingsStore? = nil, route: Route = .longForm) {
        self.settings = settings
        restore = MusicVolumeRestore(memory: settings?[AudioSettings.musicVolumes] ?? MusicVolumeMemory())
        rememberedLevel = restore.fallbackLevel
        context = Self.makeContext(route.contextSelector)
    }

    /// The level to show and to change from: what the speakers read, or the
    /// remembered level while they cannot be read. Nil when HomePad knows neither.
    var level: Double? {
        canSetVolume ? Double(volume) : rememberedLevel
    }

    /// Starts reading the speakers twice a second.
    func startUpdating() {
        guard pollTask == nil else { return }
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                self?.refresh()
                try? await Task.sleep(for: .seconds(0.5))
            }
        }
    }

    func refresh() {
        guard let context, Date() >= holdReadingsUntil else { return }
        var names: [String] = []
        var value: Float = 0
        var settable = false
        if let failure = catchingObjCException({
            let devices = (Self.get(context, "outputDevices") as? [NSObject]) ?? []
            names = devices.compactMap { (Self.get($0, "deviceName") ?? Self.get($0, "name")) as? String }
            if names.isEmpty, let name = Self.get(context, "deviceName") as? String { names = [name] }
            value = (Self.get(context, "volume") as? NSNumber)?.floatValue ?? 0
            settable = (Self.get(context, "canSetVolume") as? NSNumber)?.boolValue ?? false
        }) {
            onLog?("reading raised \(failure)")
            return
        }
        let name = Self.speakerName(names)
        speakerName = name
        volume = value
        canSetVolume = settable
        let reading = "reading \(name ?? "none") \(String(format: "%.3f", value)) settable \(settable)"
        if reading != lastReading {
            lastReading = reading
            onLog?(reading)
        }
        take(MusicVolumeRestore.Reading(
            speakers: MusicVolumeMemory.speakers(names: names), level: Double(value),
            canSet: settable, isPlaying: isMusicPlaying()
        ))
        sendPendingIfPossible()
    }

    /// Sets the speakers' volume for the person, at most every `sendInterval`
    /// while it keeps changing, and remembers it for these speakers.
    func set(_ value: Float) {
        let clamped = min(max(value, 0), 1)
        let memory = restore.memory
        restore.personChose(Double(clamped))
        memoryMayHaveChanged(from: memory)
        send(clamped)
    }

    /// Passes a reading to the restore rules and puts a level back when they say so.
    private func take(_ reading: MusicVolumeRestore.Reading) {
        let memory = restore.memory
        let action = restore.handle(reading, at: Date())
        memoryMayHaveChanged(from: memory)
        if case .restore(let level) = action {
            onLog?("restore \(String(format: "%.3f", level)), the person's last for \(reading.speakers ?? "none"), over \(String(format: "%.3f", reading.level))")
            send(Float(level))
        }
    }

    private func send(_ value: Float) {
        volume = value
        holdReadingsUntil = Date().addingTimeInterval(1)
        pending = value
        pendingSince = Date()
        guard sendTask == nil else { return }
        let wait = max(0, sendInterval - Date().timeIntervalSince(lastSent))
        sendTask = Task { [weak self] in
            if wait > 0 { try? await Task.sleep(for: .seconds(wait)) }
            self?.sendPending()
        }
    }

    /// Sends a level chosen while the speakers could not take it, once they can.
    private func sendPendingIfPossible() {
        guard pending != nil, sendTask == nil, canSetVolume else { return }
        guard Date().timeIntervalSince(pendingSince) < pendingLifetime else {
            pending = nil
            return
        }
        sendPending()
    }

    private func sendPending() {
        sendTask = nil
        let selector = NSSelectorFromString("setVolume:")
        guard let value = pending, let context, canSetVolume, context.responds(to: selector) else { return }
        pending = nil
        lastSent = Date()
        typealias Setter = @convention(c) (NSObject, Selector, Float) -> Void
        let setter = unsafeBitCast(context.method(for: selector), to: Setter.self)
        let failure = catchingObjCException { setter(context, selector, value) }
        onLog?("sent \(String(format: "%.3f", value))\(failure.map { " raised \($0)" } ?? "")")
    }

    /// Shows the new remembered level and saves the levels a second after the
    /// last change, so a drag writes the settings once.
    private func memoryMayHaveChanged(from old: MusicVolumeMemory) {
        let fallback = restore.fallbackLevel
        if fallback != rememberedLevel { rememberedLevel = fallback }
        guard restore.memory != old, let settings else { return }
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled, let self else { return }
            settings[AudioSettings.musicVolumes] = self.restore.memory
            let levels = self.restore.memory.entries.prefix(3).map { "\($0.speakers) \(String(format: "%.3f", $0.level))" }
            self.onLog?("saved \(levels.joined(separator: ", "))")
        }
    }

    /// The iPad's own speaker reads "Speaker", which HomePad calls "iPad".
    nonisolated static func speakerName(_ names: [String]) -> String? {
        guard !names.isEmpty else { return nil }
        return RouteNaming.routeName(names: names.map { $0 == "Speaker" ? RouteNaming.builtInName : $0 })
    }

    private static func makeContext(_ name: String) -> NSObject? {
        let selector = NSSelectorFromString(name)
        guard let type = NSClassFromString("AVOutputContext") as? NSObject.Type, type.responds(to: selector) else { return nil }
        var context: NSObject?
        _ = catchingObjCException { context = type.perform(selector)?.takeUnretainedValue() as? NSObject }
        return context
    }

    /// A property read through its getter, only when the getter exists.
    private static func get(_ object: NSObject, _ key: String) -> Any? {
        object.responds(to: NSSelectorFromString(key)) ? object.value(forKey: key) : nil
    }
}
