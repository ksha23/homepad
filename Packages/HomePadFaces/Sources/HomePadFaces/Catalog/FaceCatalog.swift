import Foundation

/// Every face this module provides, in gallery order.
@MainActor
enum FaceCatalog {
    /// Matches the default of `CoreSettings.defaultFaceID`.
    static let defaultFaceID = "faces.modular"

    static let all: [FaceDefinition] = [
        SmartRotationFace.definition,
        ModularFace.definition,
        HomeModularFace.definition,
        CamerasFace.definition,
        WeatherFace.definition,
        CalendarFace.definition,
        FlowFace.definition,
        PhotosFace.definition,
        AnalogFace.definition,
        NumeralsFace.definition,
        DigitalFace.definition,
        FadeFace.definition,
        WorldClockFace.definition,
        NightFace.definition,
        CrittersFace.definition,
    ].sorted { $0.sortOrder < $1.sortOrder }

    static func definition(_ id: String) -> FaceDefinition? {
        all.first { $0.id == id }
    }
}
