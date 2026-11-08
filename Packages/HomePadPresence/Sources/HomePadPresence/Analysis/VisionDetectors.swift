import CoreGraphics
import CoreML
import Foundation
@preconcurrency import Vision

/// What Vision found in one frame.
struct VisionResults {
    var faces: [VNFaceObservation] = []
    var humanCount = 0
    /// Confidence of the most certain person counted in `humanCount`.
    var humanConfidence: Double?
    /// Upper-body box of the largest (nearest) person counted, normalized.
    var nearestHuman: CGRect?
    var hand: HandPoseSample?
}

/// Reusable Vision requests for faces, people and hands. Not thread-safe:
/// use it only from the analysis queue.
final class VisionDetectors {
    private let faceRequest: VNDetectFaceRectanglesRequest = {
        let request = VNDetectFaceRectanglesRequest()
        // Revision 3 reports roll, yaw and pitch, used for alignment and enrollment.
        request.revision = VNDetectFaceRectanglesRequestRevision3
        return request
    }()
    private let humanRequest: VNDetectHumanRectanglesRequest = {
        let request = VNDetectHumanRectanglesRequest()
        request.upperBodyOnly = true
        return request
    }()
    private let handRequest: VNDetectHumanHandPoseRequest = {
        let request = VNDetectHumanHandPoseRequest()
        request.maximumHandCount = 1
        return request
    }()

    /// Runs the requested detectors in one pass over the frame.
    func detect(in frame: SensorFrame, faces: Bool, humans: Bool, hands: Bool) -> VisionResults {
        var requests: [VNRequest] = []
        if faces { requests.append(faceRequest) }
        if humans { requests.append(humanRequest) }
        if hands { requests.append(handRequest) }
        guard !requests.isEmpty else { return VisionResults() }
        let handler = VNImageRequestHandler(cvPixelBuffer: frame.pixelBuffer, orientation: frame.orientation)
        do {
            try handler.perform(requests)
        } catch {
            return VisionResults()
        }
        var results = VisionResults()
        if faces { results.faces = faceRequest.results ?? [] }
        if humans {
            let people = humanRequest.results?.filter { $0.confidence > 0.5 } ?? []
            results.humanCount = people.count
            results.humanConfidence = people.map { Double($0.confidence) }.max()
            results.nearestHuman = people.map(\.boundingBox).max { $0.width * $0.height < $1.width * $1.height }
        }
        if hands, let observation = handRequest.results?.first {
            results.hand = Self.handSample(observation, time: frame.timestamp)
        }
        return results
    }

    /// Runs the face and people requests, and the hand pose request, as
    /// asked, once on `buffer`, so their models are loaded before the first
    /// real frame needs them.
    func warmUp(on buffer: CVPixelBuffer, faces: Bool, hands: Bool) {
        var requests: [VNRequest] = []
        if faces { requests += [faceRequest, humanRequest] }
        if hands { requests.append(handRequest) }
        guard !requests.isEmpty else { return }
        try? VNImageRequestHandler(cvPixelBuffer: buffer, orientation: .right).perform(requests)
    }

    /// Runs every request on the CPU, or back where Vision chooses (the
    /// Neural Engine). After a cold boot the 11-inch took 41 s to load face
    /// detection for the Neural Engine, against 0.35 s on later launches,
    /// while the CPU does not wait for the Neural Engine. So the analyzer
    /// starts on the CPU and moves once the warm-up has loaded the models
    /// for the Neural Engine.
    func runOnCPU(_ onCPU: Bool) {
        for request in [faceRequest, humanRequest, handRequest] as [VNRequest] {
            Self.runOnCPU(onCPU, request)
        }
    }

    /// Puts every stage of `request` on the CPU, or back where Vision chooses.
    static func runOnCPU(_ onCPU: Bool, _ request: VNRequest) {
        guard let stages = try? request.supportedComputeStageDevices else { return }
        for (stage, devices) in stages {
            let cpu = devices.first { device in
                if case .cpu = device { true } else { false }
            }
            request.setComputeDevice(onCPU ? cpu : nil, for: stage)
        }
    }

    /// Converts a Vision hand pose to the recognizer's user-perspective sample.
    /// The front camera image is not mirrored, so x is flipped to match what
    /// the user sees as left and right.
    static func handSample(_ observation: VNHumanHandPoseObservation, time: TimeInterval) -> HandPoseSample? {
        guard let recognized = try? observation.recognizedPoints(.all) else { return nil }
        var points: [HandJoint: CGPoint] = [:]
        for joint in HandJoint.allCases {
            guard let point = recognized[joint.visionName], point.confidence > 0.3 else { continue }
            points[joint] = CGPoint(x: 1 - point.location.x, y: point.location.y)
        }
        return points.isEmpty ? nil : HandPoseSample(time: time, points: points)
    }
}

private extension HandJoint {
    var visionName: VNHumanHandPoseObservation.JointName {
        switch self {
        case .wrist: .wrist
        case .thumbMP: .thumbMP
        case .thumbTip: .thumbTip
        case .indexMCP: .indexMCP
        case .indexPIP: .indexPIP
        case .indexTip: .indexTip
        case .middleMCP: .middleMCP
        case .middlePIP: .middlePIP
        case .middleTip: .middleTip
        case .ringMCP: .ringMCP
        case .ringPIP: .ringPIP
        case .ringTip: .ringTip
        case .littleMCP: .littleMCP
        case .littlePIP: .littlePIP
        case .littleTip: .littleTip
        }
    }
}
