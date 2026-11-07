import Foundation

/// What Sprig, the Critters face character, is doing.
enum CritterPose: String, CaseIterable, Sendable {
    case sleeping, stretching, waving, reading, umbrella, celebrating
}

/// What Sprig is wearing or holding.
enum CritterAccessory: String, CaseIterable, Sendable {
    case none, nightcap, pumpkinHat, santaHat, partyHat, heart, scarf, sunglasses
}

/// Sprig's pose and accessory for a moment.
struct CritterLook: Hashable, Sendable {
    var pose: CritterPose
    var accessory: CritterAccessory
}

/// Decides Sprig's look from the time of day, the weather, holidays and
/// timers. Pure, so every rule is easy to test.
enum CritterBrain {
    struct Inputs {
        var date: Date
        var calendar: Calendar = .current
        var sky: SkyCondition?
        var temperatureFahrenheit: Double?
        var timerJustFinished: Bool = false
    }

    static func look(_ inputs: Inputs) -> CritterLook {
        let hour = inputs.calendar.component(.hour, from: inputs.date)
        let holiday = holidayAccessory(inputs.date, calendar: inputs.calendar)
        if inputs.timerJustFinished {
            return CritterLook(pose: .celebrating, accessory: holiday ?? .none)
        }
        if hour >= 22 || hour < 6 {
            return CritterLook(pose: .sleeping, accessory: holiday ?? .nightcap)
        }
        switch inputs.sky {
        case .rain, .thunder:
            return CritterLook(pose: .umbrella, accessory: holiday ?? .none)
        case .snow:
            return CritterLook(pose: hour < 9 ? .stretching : .waving, accessory: holiday ?? .scarf)
        default:
            break
        }
        let pose: CritterPose = hour < 9 ? .stretching : (hour >= 18 ? .reading : .waving)
        if let holiday { return CritterLook(pose: pose, accessory: holiday) }
        let isHot = (inputs.temperatureFahrenheit ?? 0) >= 80
        let isSunnyDay = inputs.sky == .clear && hour >= 10 && hour < 18
        return CritterLook(pose: pose, accessory: isHot || isSunnyDay ? .sunglasses : .none)
    }

    /// Holiday dress-up, or nil on ordinary days.
    static func holidayAccessory(_ date: Date, calendar: Calendar) -> CritterAccessory? {
        let parts = calendar.dateComponents([.month, .day], from: date)
        switch (parts.month ?? 0, parts.day ?? 0) {
        case (10, 25...31): return .pumpkinHat
        case (12, 20...26): return .santaHat
        case (12, 31), (1, 1): return .partyHat
        case (2, 14): return .heart
        default: return nil
        }
    }
}
