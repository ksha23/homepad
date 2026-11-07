import HomePadCore

// Plain-language names for Core sensing types, used in diagnostics and assistant answers.

extension PresenceSource {
    var title: String {
        switch self {
        case .trueDepth: "Face ID camera"
        case .frontCamera: "Front camera"
        case .microphone: "Microphone"
        case .touch: "Touch"
        case .none: "None"
        }
    }
}

extension ProximityLevel {
    var title: String {
        switch self {
        case .nobody: "Nobody"
        case .far: "Far"
        case .mid: "Middle"
        case .near: "Near"
        }
    }
}

extension HandGesture {
    var title: String {
        switch self {
        case .openPalm: "Open palm"
        case .pinch: "Pinch"
        }
    }
}
