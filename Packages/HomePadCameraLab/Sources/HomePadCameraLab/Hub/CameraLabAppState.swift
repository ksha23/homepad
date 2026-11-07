import HomePadCore

/// What Camera Lab keeps between launches (see `@AppState`). Within a launch
/// `CameraLabRouter` keeps the open tool. Shared by the household.
enum CameraLabAppState {
    /// The tool open when the app closed. Only tools that do not show the
    /// camera are reopened from it.
    static let tool = AppStateKey<CameraLabTool?>("cameralab.tool", default: nil)
}
