#if os(iOS)
import AVFoundation
import Observation

/// Owns the app's single `AVAudioSession`. Modules declare what they need and
/// the coordinator picks one configuration that satisfies everyone.
///
/// The trade-off it manages: AirPlay 2 multi-room (several HomePods at once)
/// needs the `.playback` category with the `.longFormAudio` route sharing policy,
/// but the microphone needs `.playAndRecord`, which only allows a single AirPlay
/// route. So while someone holds a `.longFormPlayback` claim, recording claims are
/// paused (the wake word stops). A spoken request claims `.voice`, which wins over
/// long-form playback for the moment. HomePad's own sound and microphone stay on
/// the iPad: only music goes to AirPlay.
///
///     services.audioSession.claim(.record, owner: "assistant.wakeword")
///     services.audioSession.release(owner: "assistant.wakeword")
@MainActor
@Observable
public final class AudioSessionCoordinator {
    public enum Need: String, Sendable {
        case record             // microphone input (wake word, sound recognition, intercom)
        case playback           // short sounds (TTS, chimes, timers): mixes with other apps' audio
        case mediaPlayback      // music or radio that keeps the mic: owns Now Playing, single AirPlay route
        case longFormPlayback   // music or radio that should be able to go multi-room over AirPlay 2
        case voice              // one spoken request: the iPad's microphone now, even over long-form playback
    }

    public enum Mode: String, Sendable {
        case inactive
        case playAndRecord      // mic available, single AirPlay route allowed
        case longFormPlayback   // AirPlay 2 multi-room, no mic
        case playback
    }

    public private(set) var mode: Mode = .inactive
    /// True when HomePad's audio mixes with other apps instead of interrupting them.
    /// False while HomePad plays media, so it can be the system's Now Playing app.
    public private(set) var mixesWithOthers = true
    public private(set) var claims: [String: Need] = [:]
    public private(set) var lastError: String?

    private let log = Log.make("AudioSession")
    /// With `-HomePadAudioTrace YES`, every mode change and interruption in
    /// Documents/audio-session-trace.txt.
    private let trace = DebugTrace(file: "audio-session-trace.txt", argument: "HomePadAudioTrace")

    public init() {
        NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification, object: nil, queue: .main
        ) { [weak self] note in
            let type = (note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt).flatMap(AVAudioSession.InterruptionType.init)
            let reason = (note.userInfo?[AVAudioSessionInterruptionReasonKey] as? UInt) ?? 0
            MainActor.assumeIsolated {
                self?.trace.log("interruption \(type == .began ? "began" : "ended") reason \(reason)")
                if type == .ended { self?.reactivate() }
            }
        }
        // iPadOS 27 deprecates that notice and says when audio may resume with this one.
        if #available(iOS 27.0, *) {
            NotificationCenter.default.addObserver(
                forName: AVAudioSession.resumptionRecommendationNotification, object: nil, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.trace.log("resumption recommended")
                    self?.reactivate()
                }
            }
        }
    }

    /// True when recording claims are being honored right now.
    public var isRecordingAvailable: Bool { mode == .playAndRecord }

    public func claim(_ need: Need, owner: String) {
        claims[owner] = need
        apply()
    }

    public func release(owner: String) {
        claims[owner] = nil
        apply()
    }

    /// After an interruption the session is inactive while `mode` still names its
    /// configuration, so `apply()` alone changed nothing. This activates it again.
    private func reactivate() {
        guard mode != .inactive else { return apply() }
        do {
            try AVAudioSession.sharedInstance().setActive(true)
            trace.log("reactivated as \(mode.rawValue)")
        } catch {
            lastError = error.localizedDescription
            trace.log("reactivation failed: \(error.localizedDescription)")
        }
    }

    /// Re-applies the session configuration (after interruptions or route changes).
    public func apply() {
        let needs = Set(claims.values)
        let target: Mode
        if needs.contains(.voice) {
            target = .playAndRecord
        } else if needs.contains(.longFormPlayback) {
            target = .longFormPlayback
        } else if needs.contains(.record) {
            target = .playAndRecord
        } else if needs.contains(.playback) || needs.contains(.mediaPlayback) {
            target = .playback
        } else {
            target = .inactive
        }
        // Media must not mix, or iOS will not treat HomePad as the Now Playing app.
        let mixes = !needs.contains(.mediaPlayback)
        guard target != mode || mixes != mixesWithOthers else { return }
        let session = AVAudioSession.sharedInstance()
        let mixOption: AVAudioSession.CategoryOptions = mixes ? [.mixWithOthers] : []
        // AirPlay only while HomePad itself plays media there (radio, sleep sounds).
        // With it allowed for the microphone alone, iPadOS moved HomePad's audio to
        // the HomePods whenever a spoken request changed the session, so the
        // volume slider and a restored volume landed on them at the iPad's level.
        let airPlay: AVAudioSession.CategoryOptions = needs.contains(.mediaPlayback) ? [.allowAirPlay] : []
        do {
            switch target {
            case .longFormPlayback:
                try session.setCategory(.playback, mode: .default, policy: .longFormAudio)
                try session.setActive(true)
            case .playAndRecord:
                let recordOptions: AVAudioSession.CategoryOptions = [.defaultToSpeaker, .allowBluetoothA2DP]
                try session.setCategory(.playAndRecord, mode: .default, options: recordOptions.union(mixOption).union(airPlay))
                try session.setActive(true)
            case .playback:
                try session.setCategory(.playback, mode: .default, options: mixOption)
                try session.setActive(true)
            case .inactive:
                try session.setActive(false, options: .notifyOthersOnDeactivation)
            }
            mode = target
            mixesWithOthers = mixes
            lastError = nil
            trace.log("mode \(target.rawValue) mixes \(mixes) claims \(claims.map { "\($0.key)=\($0.value.rawValue)" }.sorted())")
            log.info("Audio session mode \(target.rawValue, privacy: .public)")
        } catch {
            trace.log("mode \(target.rawValue) failed: \(error.localizedDescription)")
            lastError = error.localizedDescription
            log.error("Audio session change to \(target.rawValue, privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}
#endif
