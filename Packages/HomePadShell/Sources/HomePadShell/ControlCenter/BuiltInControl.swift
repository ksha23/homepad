/// Control Center tiles the shell provides. Module tiles come from `registry.controls`.
enum BuiltInControl: String, CaseIterable, Identifiable {
    // The default order: brightness and volume sit side by side, as in iPadOS.
    case media = "shell.media"
    case brightness = "shell.brightness"
    case volume = "shell.volume"
    case camera = "shell.camera"
    case microphone = "shell.microphone"
    case nightMode = "shell.nightMode"
    case quietHours = "shell.quietHours"
    case appearance = "shell.appearance"
    case mirror = "shell.mirror"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .media: "Now Playing"
        case .brightness: "Brightness"
        case .camera: "Camera"
        case .microphone: "Microphone"
        case .volume: "Volume"
        case .nightMode: "Night Mode"
        case .quietHours: "Quiet Hours"
        case .appearance: "Appearance"
        case .mirror: "Mirror"
        }
    }

    var systemImage: String {
        switch self {
        case .media: "play.circle.fill"
        case .brightness: "sun.max.fill"
        case .camera: "video.fill"
        case .microphone: "mic.fill"
        case .volume: "speaker.wave.2.fill"
        case .nightMode: "moon.fill"
        case .quietHours: "bell.slash.fill"
        case .appearance: "circle.lefthalf.filled"
        case .mirror: "person.crop.square"
        }
    }

    var span: GridSpan {
        switch self {
        case .media: GridSpan(columns: 2, rows: 2)
        case .brightness, .volume: GridSpan(columns: 1, rows: 2)
        case .camera, .microphone, .nightMode, .quietHours, .appearance, .mirror: .one
        }
    }

    /// Placed after module tiles in the default layout.
    var isTrailing: Bool { self == .mirror || self == .appearance }

    /// Span of a module tile from `registry.controls`.
    static let moduleTileSpan = GridSpan(columns: 2, rows: 1)
}
