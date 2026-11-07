import Foundation
import HomePadCore

/// Timing and night settings the policy needs, read from `SettingsStore` once per tick.
struct KioskTuning: Equatable {
    /// Seconds without interaction before returning to the face.
    var returnToFaceAfter: TimeInterval = 60
    /// Seconds with nobody seen before dimming.
    var dimAfter: TimeInterval = 120
    /// Seconds with nobody seen before sleeping. Zero or less never sleeps.
    var sleepAfter: TimeInterval = 600
    var nightModeAutomatic = true
    var nightModeForced = false
    var nightSchedule = NightSchedule.standard
    var calendar = Calendar.current

    @MainActor
    init(settings: SettingsStore) {
        returnToFaceAfter = max(5, settings[CoreSettings.returnToFaceAfter])
        dimAfter = max(0, settings[ShellSettings.dimAfterMinutes]) * 60
        sleepAfter = settings[CoreSettings.sleepAfterMinutes] * 60
        nightModeAutomatic = settings[CoreSettings.nightModeAutomatic]
        nightModeForced = settings[ShellSettings.nightModeForced]
        nightSchedule = settings[ShellSettings.nightSchedule]
    }

    init() {}
}

/// One instant's worth of input to the policy.
struct KioskInputs: Equatable {
    var now: Date
    /// Last touch or wake event (doorbell, timer, assistant...).
    var lastInteraction: Date
    /// Last interaction or close presence (someone near or looking at the screen).
    var lastEngagement: Date
    var presence: PresenceSnapshot
    var tuning: KioskTuning
}

/// What the display should do right now.
struct KioskState: Equatable {
    var condition: DisplayCondition
    /// Someone touched the screen or a wake event fired within `returnToFaceAfter`.
    var isInteracting: Bool
    /// Night palette and night brightness apply.
    var isNight: Bool

    static let initial = KioskState(condition: .ambient, isInteracting: false, isNight: false)
}

/// The kiosk state machine as a pure function, so it is easy to test.
///
/// Precedence, first match wins:
/// 1. Nobody seen for `sleepAfter` and nobody interacting: `.sleeping` (near-black).
/// 2. Night (forced, or the scheduled hours unless the room is lit): `.night`.
/// 3. Interacting: `.active`.
/// 4. Nobody present and nobody seen for `dimAfter`: `.dimmed`.
/// 5. Otherwise `.ambient` (the face at normal brightness).
enum DisplayConditionPolicy {
    static func evaluate(_ inputs: KioskInputs) -> KioskState {
        let tuning = inputs.tuning
        let isInteracting = inputs.now.timeIntervalSince(inputs.lastInteraction) < tuning.returnToFaceAfter
        let lastSeen = max(inputs.lastEngagement, inputs.lastInteraction, inputs.presence.lastActivity)
        let unseenFor = inputs.now.timeIntervalSince(lastSeen)
        let night = isNight(now: inputs.now, ambientLight: inputs.presence.ambientLight, tuning: tuning)

        let condition: DisplayCondition
        if !isInteracting && tuning.sleepAfter > 0 && unseenFor >= tuning.sleepAfter {
            condition = .sleeping
        } else if night {
            condition = .night
        } else if isInteracting {
            condition = .active
        } else if !inputs.presence.isSomeonePresent && unseenFor >= tuning.dimAfter {
            condition = .dimmed
        } else {
            condition = .ambient
        }
        return KioskState(condition: condition, isInteracting: isInteracting, isNight: night)
    }

    /// Night when forced, or (automatic only) during the scheduled hours unless the
    /// room is normally or brightly lit. The camera's light estimate never starts
    /// night mode outside the schedule: a hand over the front camera looks exactly
    /// like a dark room, so darkness alone would switch to night by accident. It can
    /// only keep night off when the lights are on.
    static func isNight(now: Date, ambientLight: AmbientLight?, tuning: KioskTuning) -> Bool {
        if tuning.nightModeForced { return true }
        guard tuning.nightModeAutomatic, tuning.nightSchedule.contains(now, calendar: tuning.calendar) else { return false }
        switch ambientLight {
        case .normal, .bright:
            return false
        case .dark, .dim, nil:
            return true
        }
    }
}
