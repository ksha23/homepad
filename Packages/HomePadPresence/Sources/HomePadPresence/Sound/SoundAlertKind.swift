import Foundation
import HomePadCore

/// Household sounds HomePad listens for, mapped to the labels of Apple's
/// built-in SoundAnalysis classifier (`SNClassifierIdentifier.version1`).
///
/// The SDK label list was read from `SNClassifySoundRequest.knownClassifications`
/// (303 labels). It has `smoke_detector` but no carbon monoxide or "fire alarm"
/// label (`fire` is crackling flames). CO alarms beep in a pattern close to smoke
/// alarms and will most likely register as `smoke_detector` or not at all, so
/// HomePad treats `smoke_detector` as "smoke or CO alarm" and says so in the UI.
public enum SoundAlertKind: String, CaseIterable, Codable, Identifiable, Sendable {
    case smokeAlarm
    case doorbell
    case knock
    case dogBark
    case babyCrying
    case glassBreaking
    case siren

    public var id: String { rawValue }

    /// SDK classifier labels that map to this kind.
    var classifierLabels: [String] {
        switch self {
        case .smokeAlarm: ["smoke_detector"]
        case .doorbell: ["door_bell"]
        case .knock: ["knock"]
        case .dogBark: ["dog_bark", "dog_bow_wow"]
        case .babyCrying: ["baby_crying"]
        case .glassBreaking: ["glass_breaking"]
        case .siren: ["siren", "ambulance_siren", "police_siren", "fire_engine_siren", "civil_defense_siren"]
        }
    }

    /// The label posted in `.soundDetected(label:confidence:)`, shared in Core.
    var eventLabel: String {
        switch self {
        case .smokeAlarm: SoundEventLabel.smokeAlarm
        case .doorbell: SoundEventLabel.doorbell
        case .knock: SoundEventLabel.knock
        case .dogBark: SoundEventLabel.dogBark
        case .babyCrying: SoundEventLabel.babyCrying
        case .glassBreaking: SoundEventLabel.glassBreaking
        case .siren: SoundEventLabel.siren
        }
    }

    var title: String {
        switch self {
        case .smokeAlarm: "Smoke or CO alarm"
        case .doorbell: "Doorbell"
        case .knock: "Knocking"
        case .dogBark: "Dog barking"
        case .babyCrying: "Baby crying"
        case .glassBreaking: "Glass breaking"
        case .siren: "Siren"
        }
    }

    var systemImage: String {
        switch self {
        case .smokeAlarm: "smoke.fill"
        case .doorbell: "bell.fill"
        case .knock: "door.left.hand.closed"
        case .dogBark: "dog.fill"
        case .babyCrying: "figure.and.child.holdinghands"
        case .glassBreaking: "wineglass.fill"
        case .siren: "light.beacon.max.fill"
        }
    }

    /// Headline for the full-screen alert.
    var alertHeadline: String {
        switch self {
        case .smokeAlarm: "Smoke or CO Alarm"
        default: title
        }
    }

    /// Life-safety sounds take over the screen with a full-screen alert.
    var isCritical: Bool { self == .smokeAlarm }

    /// Seconds before the same kind may alert again.
    var cooldown: TimeInterval {
        switch self {
        case .smokeAlarm: 60
        case .doorbell, .knock: 15
        case .dogBark, .babyCrying, .siren: 45
        case .glassBreaking: 30
        }
    }

    /// Detections inside `confirmationWindow` needed before alerting. Short,
    /// sharp sounds alert on one hit, sustained sounds need two.
    var requiredHits: Int {
        switch self {
        case .glassBreaking, .knock, .doorbell: 1
        case .smokeAlarm, .dogBark, .babyCrying, .siren: 2
        }
    }

    /// The kind an SDK label belongs to.
    static func kind(forClassifierLabel label: String) -> SoundAlertKind? {
        allCases.first { $0.classifierLabels.contains(label) }
    }
}
