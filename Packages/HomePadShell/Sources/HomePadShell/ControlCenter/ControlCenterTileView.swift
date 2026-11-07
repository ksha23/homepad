import HomePadCore
import HomePadUI
import SwiftUI

/// Draws one Control Center tile: a built-in control or a module's tile.
struct ControlCenterTileView: View {
    let tileID: String
    @Environment(AppServices.self) private var services
    @Environment(ModuleRegistry.self) private var registry
    @Environment(SettingsStore.self) private var settings
    @Environment(ShellNavigator.self) private var navigator
    @Environment(KioskController.self) private var kiosk

    var body: some View {
        if let builtIn = BuiltInControl(rawValue: tileID) {
            builtInTile(builtIn)
        } else if let control = registry.controls.first(where: { $0.id == tileID }) {
            control.makeView()
        }
    }

    @ViewBuilder
    private func builtInTile(_ control: BuiltInControl) -> some View {
        switch control {
        case .media:
            MediaControlTile()
        case .brightness:
            BrightnessControlTile()
        case .volume:
            SystemVolumeTile()
        case .camera:
            let isOn = settings[CoreSettings.cameraEnabled]
            ToggleTile("Camera", systemImage: isOn ? "video.fill" : "video.slash.fill", isOn: Binding(
                get: { isOn },
                set: { value in
                    settings[CoreSettings.cameraEnabled] = value
                    services.capture.camerasAllowed = value
                }
            ))
        case .microphone:
            let isOn = settings[CoreSettings.microphoneEnabled]
            ToggleTile("Microphone", systemImage: isOn ? "mic.fill" : "mic.slash.fill",
                       isOn: settings.binding(CoreSettings.microphoneEnabled))
        case .nightMode:
            ToggleTile("Night", systemImage: "moon.fill", isOn: Binding(
                get: { settings[ShellSettings.nightModeForced] },
                set: { value in
                    settings[ShellSettings.nightModeForced] = value
                    kiosk.tick()
                }
            ), onTint: Theme.nightRed)
        case .quietHours:
            let isOn = settings[CoreSettings.quietHoursEnabled]
            ToggleTile("Quiet", systemImage: isOn ? "bell.slash.fill" : "bell.fill",
                       isOn: settings.binding(CoreSettings.quietHoursEnabled), onTint: .indigo)
        case .appearance:
            AppearanceControlTile()
        case .mirror:
            RoundControlButton("Mirror", systemImage: control.systemImage,
                               isEnabled: registry.app(KnownAppID.mirror) != nil) {
                navigator.open(appID: KnownAppID.mirror)
            }
        }
    }
}
