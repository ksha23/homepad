import Foundation

/// When a Smart Rotation rule applies.
enum RotationTrigger: Codable, Hashable, Sendable {
    /// The display is in night mode (dark room).
    case night
    /// Between two times of day, in minutes after midnight. Wraps past midnight.
    case timeOfDay(startMinute: Int, endMinute: Int)
    /// Something happened recently, such as the doorbell ringing.
    case activity(FaceActivity, withinSeconds: Double)
    /// A recognized household member is here. Shows their own current face.
    case memberFace

    var title: String {
        switch self {
        case .night:
            return "In Night Mode"
        case .timeOfDay(let start, let end):
            return "\(Self.clockString(start)) to \(Self.clockString(end))"
        case .activity(let activity, let seconds):
            let minutes = max(Int((seconds / 60).rounded()), 1)
            return "\(activity.title), for \(minutes) min"
        case .memberFace:
            return "A Recognized Person Is Here"
        }
    }

    var systemImage: String {
        switch self {
        case .night: "moon.fill"
        case .timeOfDay: "clock.fill"
        case .activity(.doorbell, _): "bell.fill"
        case .activity(.motion, _): "figure.walk.motion"
        case .activity(.timerFinished, _): "timer"
        case .memberFace: "person.crop.circle.fill"
        }
    }

    /// "6:00 AM" for 360, in the user's locale.
    static func clockString(_ minutes: Int, calendar: Calendar = .current) -> String {
        let start = calendar.startOfDay(for: Date(timeIntervalSinceReferenceDate: 0))
        let date = start.addingTimeInterval(TimeInterval(minutes * 60))
        return date.formatted(.dateTime.hour().minute())
    }
}

/// One Smart Rotation rule: when the trigger applies, show a face.
struct RotationRule: Codable, Hashable, Identifiable, Sendable {
    var id: UUID
    var isEnabled: Bool
    var trigger: RotationTrigger
    /// Face kind to show. Ignored by `.memberFace`, which shows the member's own face.
    var faceID: String

    init(id: UUID = UUID(), isEnabled: Bool = true, trigger: RotationTrigger, faceID: String) {
        self.id = id
        self.isEnabled = isEnabled
        self.trigger = trigger
        self.faceID = faceID
    }
}

/// Every Smart Rotation choice: rules checked top to bottom, then the fallback.
struct RotationSettings: Codable, Hashable, Sendable {
    var rules: [RotationRule]
    /// "Otherwise show": the face when no rule applies.
    var fallbackFaceID: String

    static let defaults = RotationSettings(
        rules: [
            RotationRule(id: fixedID(1), trigger: .activity(.doorbell, withinSeconds: 120), faceID: "faces.cameras"),
            RotationRule(id: fixedID(2), trigger: .night, faceID: "faces.night"),
            RotationRule(id: fixedID(3), trigger: .memberFace, faceID: ""),
            RotationRule(id: fixedID(4), trigger: .timeOfDay(startMinute: 6 * 60, endMinute: 10 * 60), faceID: "faces.modular"),
        ],
        fallbackFaceID: "faces.photos"
    )

    private static func fixedID(_ number: Int) -> UUID {
        UUID(uuidString: String(format: "A0700000-0000-4000-8000-%012d", number)) ?? UUID()
    }
}
