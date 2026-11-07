import HomePadCore

/// What the Faces app keeps between openings (see `@AppState`). Shared by the
/// household: anyone may look at anyone's faces from the picker.
enum FacesAppState {
    /// Whose faces the app lists: everyone's or one member's.
    static let owner = AppStateKey("faces.owner", default: FaceOwner.household)
}
