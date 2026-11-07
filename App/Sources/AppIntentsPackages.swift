import AppIntents
import HomePadConnect

/// Pulls App Intents defined in feature packages into the app's intents
/// metadata, so Siri, Shortcuts and Spotlight see them.
struct HomePadAppIntentsPackage: AppIntentsPackage {
    static var includedPackages: [any AppIntentsPackage.Type] {
        [HomePadConnectIntents.self]
    }
}
