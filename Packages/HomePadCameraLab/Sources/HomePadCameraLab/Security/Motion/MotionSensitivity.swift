import Foundation

/// The three curated motion sensitivity levels offered in Settings.
enum MotionSensitivity: String, Codable, CaseIterable, Identifiable, Sendable {
    case low
    case medium
    case high

    var id: String { rawValue }

    var title: String {
        switch self {
        case .low: "Low"
        case .medium: "Medium"
        case .high: "High"
        }
    }

    var detail: String {
        switch self {
        case .low: "Only large movement close to the camera."
        case .medium: "A person walking through the room."
        case .high: "Small movement, including pets."
        }
    }

    var configuration: MotionDetector.Configuration {
        switch self {
        case .low: MotionDetector.Configuration(pixelThreshold: 40, minimumChangedFraction: 0.03, requiredConsecutiveFrames: 3)
        case .medium: MotionDetector.Configuration(pixelThreshold: 28, minimumChangedFraction: 0.012)
        case .high: MotionDetector.Configuration(pixelThreshold: 18, minimumChangedFraction: 0.004)
        }
    }
}
