import Foundation
#if canImport(UIKit)
import UIKit
#endif

/// What this copy of the app is. The same app runs as the always-on HomePad on
/// an iPad, and as the companion remote on an iPhone or a Mac.
///
/// The app picks its root screen by it, and the iPad's own sensing (presence
/// with its camera and sounds, and the wake phrase) runs only on a HomePad. A
/// companion uses the microphone only while someone holds the intercom's
/// talk button.
public enum AppRole: Sendable {
    case homePad
    case companion

    @MainActor
    public static var current: AppRole {
        #if canImport(UIKit)
        if ProcessInfo.processInfo.isiOSAppOnMac { return .companion }
        return UIDevice.current.userInterfaceIdiom == .pad ? .homePad : .companion
        #else
        return .companion
        #endif
    }
}
