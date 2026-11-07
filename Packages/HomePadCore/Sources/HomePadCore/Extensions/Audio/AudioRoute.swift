import Foundation
#if os(iOS)
import AVFoundation
#endif

/// Shared facts about where sound is going right now. The Audio module owns
/// routing, and any module may read these (for example to pick a quieter chime
/// when AirPods are in, or to skip speaking an answer out loud at night).
///
///     if AudioRoute.isHeadphonesActive { ... }
///
/// The Audio module also posts `.custom(name: AudioRoute.headphonesChangedEvent,
/// payload: .bool(isActive))` on `services.events` whenever headphones connect
/// or disconnect.
public enum AudioRoute {
    /// Name of the `.custom` event posted when headphones connect or disconnect.
    /// The payload is `.bool(true)` when headphones became active.
    public static let headphonesChangedEvent = "audio.headphonesChanged"

    /// Outputs of the current system route. Empty where there is no audio session.
    public static var currentPorts: [AudioRoutePort] {
        #if os(iOS)
        AVAudioSession.sharedInstance().currentRoute.outputs.map {
            AudioRoutePort(name: $0.portName, uid: $0.uid, portType: $0.portType.rawValue)
        }
        #else
        []
        #endif
    }

    /// True when sound currently plays through headphones (AirPods, Bluetooth or wired).
    public static var isHeadphonesActive: Bool {
        currentPorts.contains(where: \.isHeadphones)
    }
}
