import Foundation
import HomePadCore

/// The kiosk's screen brightness. With HomePad's own levels it ramps to the
/// level for the display condition and follows the room's light calmly
/// (`BrightnessStabilizer`). With iPadOS auto-brightness it only dims below
/// the system's level for nobody nearby, night and sleep, and hands that level
/// back afterwards. A level picked by hand in Control Center holds until the
/// display condition changes.
@MainActor
final class KioskBrightness {
    private let ramp: BrightnessRamp
    private let dependencies: KioskDependencies
    private var stabilizer = BrightnessStabilizer()
    /// The system's brightness when HomePad started dimming, handed back on wake.
    private var systemLevelBeforeDimming: Double?
    private var manual: (value: Double, condition: DisplayCondition)?

    init(dependencies: KioskDependencies) {
        self.dependencies = dependencies
        ramp = BrightnessRamp(control: dependencies.brightness)
    }

    /// Brightness right now, for sliders.
    var current: Double { ramp.current }

    /// Remembers the brightness the user had before HomePad took over.
    func takeOver() {
        ramp.saveUserBrightness()
    }

    /// Puts the user's brightness back (HomePad went to the background).
    func handBack() {
        ramp.restoreUserBrightness()
    }

    /// A level picked by hand. It holds until the condition changes.
    func setManual(_ value: Double, condition: DisplayCondition) {
        manual = (value, condition)
        ramp.ramp(to: value, duration: 0)
    }

    /// Ramps toward the brightness for the kiosk state and the room's light.
    func update(for state: KioskState, presence snapshot: PresenceSnapshot, settings: SettingsStore, cap: Double) {
        if let manual, manual.condition == state.condition { return }
        if manual != nil {
            manual = nil
            stabilizer.reset()
        }
        if settings[ShellSettings.followSystemBrightness] {
            followSystemBrightness(state, levels: settings[ShellSettings.brightnessLevels], cap: cap)
            return
        }
        systemLevelBeforeDimming = nil
        let target = settings[ShellSettings.brightnessLevels].target(
            for: state, ambientLight: snapshot.ambientLight, ambientLux: snapshot.ambientLux,
            adaptToRoomLight: settings[ShellSettings.adaptToRoomLight], cap: cap
        )
        let rounded = (target * 100).rounded() / 100
        switch stabilizer.update(target: rounded, condition: state.condition, now: dependencies.clock()) {
        case .none:
            return
        case .condition(let value):
            let duration = value > ramp.current ? dependencies.brightenDuration : dependencies.darkenDuration
            ramp.ramp(to: value, duration: duration)
        case .roomLight(let value):
            // Following the room is gradual, so nobody notices the change happening.
            ramp.ramp(to: value, duration: dependencies.roomLightDuration)
        }
    }

    /// iPadOS auto-brightness drives the screen while it is in use or showing the
    /// face. HomePad only lowers it for nobody nearby, night and sleep, relative to
    /// the level the system had chosen, and gives that level back afterwards.
    private func followSystemBrightness(_ state: KioskState, levels: BrightnessLevels, cap: Double) {
        switch state.condition {
        case .active, .ambient:
            guard let level = systemLevelBeforeDimming else { return }
            systemLevelBeforeDimming = nil
            ramp.ramp(to: level, duration: dependencies.brightenDuration)
        case .dimmed, .night, .sleeping:
            let base = systemLevelBeforeDimming ?? ramp.current
            if systemLevelBeforeDimming == nil { systemLevelBeforeDimming = base }
            ramp.ramp(to: Self.dimmedLevel(for: state, base: base, levels: levels, cap: cap),
                      duration: dependencies.darkenDuration)
        }
    }

    /// How far to dim below the system's level for a condition. Never brighter than the system.
    nonisolated static func dimmedLevel(for state: KioskState, base: Double, levels: BrightnessLevels, cap: Double = 1) -> Double {
        let level: Double
        switch state.condition {
        case .dimmed:
            // The Nobody Nearby slider is relative to In Use, applied to the system's level.
            level = base * (levels.active > 0 ? levels.dimmed / levels.active : 0.25)
        case .night:
            level = levels.night + (state.isInteracting ? 0.12 : 0)
        case .sleeping:
            level = 0
        case .active, .ambient:
            level = base
        }
        return (min(max(level, 0), base, cap) * 100).rounded() / 100
    }
}
