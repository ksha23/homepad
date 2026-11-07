import Foundation
import HomePadCore

/// What Smart Rotation knows when it decides.
struct RotationContext {
    var now: Date
    var calendar: Calendar = .current
    var displayCondition: DisplayCondition
    var lastActivity: [FaceActivity: Date] = [:]
    /// The recognized member's own current face, if they have one.
    var memberFaceID: String?
    /// Face kinds that are registered and can be shown.
    var availableFaceIDs: Set<String>
}

/// The face Smart Rotation picked and the rule that picked it (nil for the fallback).
struct RotationDecision: Equatable {
    var faceID: String
    var ruleID: UUID?
}

/// Pure rule evaluation for the Smart Rotation face. The first enabled rule
/// that applies and names a showable face wins.
enum RotationEngine {
    static let selfID = "faces.auto"
    static let lastResortID = "faces.modular"

    static func decide(_ settings: RotationSettings, context: RotationContext) -> RotationDecision {
        for rule in settings.rules where rule.isEnabled {
            if let faceID = face(for: rule, context: context), isShowable(faceID, context) {
                return RotationDecision(faceID: faceID, ruleID: rule.id)
            }
        }
        return RotationDecision(faceID: fallback(settings.fallbackFaceID, context: context), ruleID: nil)
    }

    /// The face a rule asks for when its trigger applies, else nil.
    static func face(for rule: RotationRule, context: RotationContext) -> String? {
        switch rule.trigger {
        case .night:
            return context.displayCondition == .night ? rule.faceID : nil
        case .timeOfDay(let start, let end):
            return isMinute(minuteOfDay(context.now, calendar: context.calendar), between: start, and: end) ? rule.faceID : nil
        case .activity(let activity, let window):
            guard let date = context.lastActivity[activity] else { return nil }
            let age = context.now.timeIntervalSince(date)
            return age >= -1 && age <= window ? rule.faceID : nil
        case .memberFace:
            return context.memberFaceID
        }
    }

    /// True when `minute` is in `[start, end)`, wrapping past midnight when start > end.
    static func isMinute(_ minute: Int, between start: Int, and end: Int) -> Bool {
        if start == end { return true }
        if start < end { return minute >= start && minute < end }
        return minute >= start || minute < end
    }

    static func minuteOfDay(_ date: Date, calendar: Calendar) -> Int {
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        return (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
    }

    private static func isShowable(_ faceID: String, _ context: RotationContext) -> Bool {
        !faceID.isEmpty && faceID != selfID && context.availableFaceIDs.contains(faceID)
    }

    private static func fallback(_ preferred: String, context: RotationContext) -> String {
        if isShowable(preferred, context) { return preferred }
        if isShowable(lastResortID, context) { return lastResortID }
        return context.availableFaceIDs.filter { $0 != selfID }.sorted().first ?? lastResortID
    }
}
