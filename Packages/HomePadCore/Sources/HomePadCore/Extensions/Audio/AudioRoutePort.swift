import Foundation

/// One output of the current system audio route, classified for HomePad.
///
/// Classification works on the raw `AVAudioSession.Port` strings, so it builds on
/// every platform and is easy to test. The Audio module owns routing and fills
/// these in from `AVAudioSession.currentRoute`.
public struct AudioRoutePort: Hashable, Sendable {
    /// Raw values of the `AVAudioSession.Port` constants HomePad cares about.
    public enum PortType {
        public static let builtInSpeaker = "Speaker"
        public static let builtInReceiver = "Receiver"
        public static let headphones = "Headphones"
        public static let bluetoothA2DP = "BluetoothA2DPOutput"
        public static let bluetoothLE = "BluetoothLE"
        public static let bluetoothHFP = "BluetoothHFP"
        public static let airPlay = "AirPlay"
        public static let usbAudio = "USBAudio"
        public static let hdmi = "HDMIOutput"
        public static let lineOut = "LineOut"
        public static let carAudio = "CarAudio"
    }

    /// The system's name for the port, for example "Kitchen" or "Kyle's AirPods Pro".
    public var name: String
    /// System-assigned unique identifier of the port.
    public var uid: String
    /// Raw `AVAudioSession.Port` value.
    public var portType: String
    public var kind: AudioOutputKind
    /// True for AirPods, other Bluetooth headphones and wired headphones.
    public var isHeadphones: Bool

    public init(name: String, uid: String, portType: String) {
        self.name = name
        self.uid = uid
        self.portType = portType
        let classification = Self.classify(portType: portType, name: name)
        self.kind = classification.kind
        self.isHeadphones = classification.isHeadphones
    }

    /// Maps a port type and name to an output kind and a headphones flag.
    ///
    /// iOS reports Bluetooth speakers and Bluetooth headphones with the same port
    /// types, so the name decides. Names that clearly belong to earbuds win, then
    /// names that clearly belong to speakers, and anything else counts as headphones
    /// because that is what an iPad on a nightstand usually pairs with.
    public static func classify(portType: String, name: String) -> (kind: AudioOutputKind, isHeadphones: Bool) {
        switch portType {
        case PortType.airPlay:
            return (.airPlay, false)
        case PortType.builtInSpeaker, PortType.builtInReceiver:
            return (.builtInSpeaker, false)
        case PortType.headphones:
            return (.wired, true)
        case PortType.bluetoothA2DP, PortType.bluetoothLE, PortType.bluetoothHFP:
            return (.bluetooth, nameSuggestsHeadphones(name, defaultValue: true))
        case PortType.usbAudio:
            return (.wired, nameSuggestsHeadphones(name, defaultValue: false))
        default:
            return (.wired, false)
        }
    }

    private static let headphoneWords = ["airpods", "buds", "headphone", "headset", "earphone", "earpods"]
    private static let speakerWords = [
        "speaker", "soundbar", "sound bar", "homepod", "sonos", "boom", "soundlink",
        "pill", "echo", "flip", "charge", "roam", "car", "tv", "receiver",
    ]

    private static func nameSuggestsHeadphones(_ name: String, defaultValue: Bool) -> Bool {
        let lowered = name.lowercased()
        if headphoneWords.contains(where: lowered.contains) { return true }
        if speakerWords.contains(where: lowered.contains) { return false }
        return defaultValue
    }
}
