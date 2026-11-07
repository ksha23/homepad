import HomePadAssistant
import HomePadAudio
import HomePadCameraLab
import HomePadComms
import HomePadConnect
import HomePadCore
import HomePadFaces
import HomePadKitchen
import HomePadPersonal
import HomePadPresence
import HomePadShell
import HomePadSmartHome

/// Every feature module, in registration order. Services a module replaces
/// are visible to modules registered after it, so infrastructure comes first.
enum Modules {
    @MainActor
    static let all: [any HomePadModule.Type] = [
        PresenceModule.self,     // presence + kiosk sensing (TrueDepth, camera, sounds)
        SmartHomeModule.self,    // HomeKit + Home Assistant
        AudioModule.self,        // AirPlay routing, music
        PersonalModule.self,     // calendar, reminders, weather, photos, clocks
        KitchenModule.self,      // recipes, cooking mode, timers
        CameraLabModule.self,    // back-camera features
        ConnectModule.self,      // Siri, Handoff, iCloud, intercom, companions
        CommsModule.self,        // Messages as each member's Apple ID, through a Mac hub
        AssistantModule.self,    // AI providers and voice, after everything that registers tools
        FacesModule.self,        // faces read every service above
        ShellModule.self,        // shell settings, Control Center, People
    ]
}
