import Foundation

/// The one-tap "Play on Living Room?" prompt.
struct RoutePrompt: Identifiable, Equatable {
    let id = UUID()
    let speakerName: String
}
