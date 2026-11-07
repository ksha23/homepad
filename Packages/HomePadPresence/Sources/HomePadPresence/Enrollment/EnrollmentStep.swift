import Foundation

/// One head pose captured during face enrollment. Several angles at two
/// distances make recognition hold up when someone glances at the screen from
/// the side or from where they usually sit.
///
/// Traces from a HomePad in daily use show most recognition samples come from 0.7 to
/// 0.9 m, where scores were about 0.1 lower than at 0.5 m, so the last two
/// steps are taken sitting back.
enum EnrollmentStep: Int, CaseIterable, Sendable {
    case center
    case sideA
    case sideB
    case chinUp
    case chinDown
    case sitBack
    case sitBackTurn

    var instruction: String {
        switch self {
        case .center: "Look straight at the screen"
        case .sideA: "Slowly turn your head to one side"
        case .sideB: "Now turn to the other side"
        case .chinUp: "Tilt your chin up a little"
        case .chinDown: "Tilt your chin down a little"
        case .sitBack: "Sit back where you usually sit"
        case .sitBackTurn: "Slowly turn your head side to side"
        }
    }

    var systemImage: String {
        switch self {
        case .center: "face.smiling"
        case .sideA: "arrow.left.and.right"
        case .sideB: "arrow.left.and.right"
        case .chinUp: "arrow.up"
        case .chinDown: "arrow.down"
        case .sitBack: "arrow.down.right.and.arrow.up.left"
        case .sitBackTurn: "arrow.left.and.right"
        }
    }

    /// How far from the iPad the step wants the face.
    var distance: EnrollmentDistance {
        switch self {
        case .sitBack, .sitBackTurn: .far
        default: .near
        }
    }

    /// Samples the step keeps.
    var samplesNeeded: Int {
        switch self {
        case .sideA, .sideB, .sitBackTurn: 4
        default: 3
        }
    }

    /// Degrees of yaw or pitch each new sample must differ from the step's
    /// earlier ones, so turning steps spread over the range instead of
    /// repeating one angle.
    var poseSpreadDegrees: Double {
        switch self {
        case .center, .sitBack: 0
        case .chinUp, .chinDown: 4
        case .sideA, .sideB: 5
        case .sitBackTurn: 6
        }
    }

    /// The hint while the pose is not reached yet.
    var poseHint: String {
        switch self {
        case .center, .sitBack: "Look straight at the screen"
        default: "Keep going"
        }
    }

    /// The hint while the pose repeats one already captured.
    var spreadHint: String {
        switch self {
        case .chinUp, .chinDown: "Move your head a little"
        default: "Keep turning slowly"
        }
    }

    /// Whether a face pose (Vision yaw and pitch, radians) fits this step.
    /// `firstSide` is the yaw sign captured in `.sideA`, so `.sideB` asks for the other one.
    func matches(yaw: Double, pitch: Double, firstSide: Double?) -> Bool {
        let degrees = 180 / Double.pi
        let yawDeg = yaw * degrees
        let pitchDeg = pitch * degrees
        switch self {
        case .center:
            return abs(yawDeg) < 10 && abs(pitchDeg) < 10
        case .sideA:
            return (15...45).contains(abs(yawDeg)) && abs(pitchDeg) < 15
        case .sideB:
            guard let firstSide else { return false }
            return (15...45).contains(abs(yawDeg)) && yawDeg.sign != firstSide.sign && abs(pitchDeg) < 15
        case .chinUp:
            // Vision reports positive pitch when the head nods down. Some yaw is
            // fine, so the samples also cover the diagonals.
            return pitchDeg <= -8 && abs(yawDeg) < 20
        case .chinDown:
            return pitchDeg >= 8 && abs(yawDeg) < 20
        case .sitBack:
            return abs(yawDeg) < 12 && abs(pitchDeg) < 12
        case .sitBackTurn:
            return (8...40).contains(abs(yawDeg)) && abs(pitchDeg) < 15
        }
    }
}

/// The two distances enrollment captures.
enum EnrollmentDistance: Sendable {
    /// Arm's length, as before.
    case near
    /// Where someone sits when they glance at the iPad.
    case far

    /// Farthest a near sample may be, when depth measures it.
    static let nearMaxMeters = 0.65
    /// Where far samples are taken, when depth measures it. Recognition
    /// samples mostly come from 0.7 to 0.9 m.
    static let farMeters = 0.7...1.1
    /// Smallest near face, as a share of the image width (the old rule).
    static let nearMinWidth = 0.15
    /// Without depth, a far face is this share of the near faces' width,
    /// about 1.4 to 2.5 times as far away.
    static let farWidthRatio = 0.4...0.7
    /// Smallest far face, so its crop is not mostly upscaling.
    static let farMinWidth = 0.05
}

/// What the enrollment camera saw in one frame.
struct EnrollmentObservation: Sendable {
    var faceCount: Int
    /// Width of the largest face as a fraction of the image width.
    var faceWidth: Double
    var yaw: Double?
    var pitch: Double?
    /// Embedding of the face, when exactly one face was seen.
    var sample: FaceEmbeddingSample?
    /// Capture time in seconds.
    var time: TimeInterval = 0
    /// Mean brightness of the face (0 to 1), when measured.
    var faceLuma: Double?
}
