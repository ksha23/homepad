import HomePadCore

/// The distance the face editor previews a face at: from across the room,
/// or up close, where faces add detail (Modular's widgets, seconds hands).
enum EditorDistance: String, CaseIterable, Identifiable, Sendable {
    case far
    case near

    var id: String { rawValue }

    var title: String {
        switch self {
        case .far: "Across the Room"
        case .near: "Up Close"
        }
    }

    /// The proximity the preview draws the face at.
    var proximity: ProximityLevel {
        switch self {
        case .far: .far
        case .near: .near
        }
    }
}

/// Which distance the editor shows. The person's own pick holds on every
/// page, except a page whose option only shows at one distance, which
/// switches to it while it is open (`FaceOption.previewDistance`).
struct EditorDistanceState: Equatable, Sendable {
    /// What the person picked by hand. Across the room until they pick.
    private(set) var chosen: EditorDistance
    /// What the preview shows now.
    private(set) var shown: EditorDistance

    init(chosen: EditorDistance = .far) {
        self.chosen = chosen
        shown = chosen
    }

    /// Opens a page: its option's distance if it declares one, else the person's pick.
    mutating func open(_ option: FaceOption?) {
        shown = option?.previewDistance ?? chosen
    }

    /// The person flipped the control by hand.
    mutating func pick(_ distance: EditorDistance) {
        chosen = distance
        shown = distance
    }
}
