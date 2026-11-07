import ARKit
import HomePadCore
import Observation
import RoomPlan

/// Drives RoomPlan's `RoomCaptureView` for one or more rooms. Every room in a
/// session shares one ARSession, so the rooms line up in the same coordinates.
@MainActor
@Observable
final class RoomScanController: NSObject, @preconcurrency RoomCaptureViewDelegate, @preconcurrency RoomCaptureSessionDelegate {
    enum Phase: Equatable {
        case scanning
        case processing
        case roomReady
        case failed(String)
    }

    private(set) var phase: Phase = .scanning
    private(set) var rooms: [CapturedRoom] = []
    private(set) var instruction: String?

    @ObservationIgnored let arSession = ARSession()
    @ObservationIgnored private(set) lazy var captureView: RoomCaptureView = {
        let view = RoomCaptureView(frame: .zero, arSession: arSession)
        view.delegate = self
        view.captureSession.delegate = self
        return view
    }()
    @ObservationIgnored private let log = Log.make("CameraLab.RoomScan")

    override init() {
        super.init()
    }

    required init?(coder: NSCoder) {
        nil
    }

    func encode(with coder: NSCoder) {}

    func startRoom() {
        phase = .scanning
        instruction = nil
        var configuration = RoomCaptureSession.Configuration()
        configuration.isCoachingEnabled = true
        captureView.captureSession.run(configuration: configuration)
    }

    /// Ends this room. RoomPlan processes it and calls back with the result.
    func finishRoom() {
        phase = .processing
        captureView.captureSession.stop(pauseARSession: false)
    }

    /// Stops everything, for Cancel or Done.
    func stopAll() {
        captureView.captureSession.stop(pauseARSession: true)
        arSession.pause()
    }

    // MARK: RoomCaptureViewDelegate

    func captureView(shouldPresent roomDataForProcessing: CapturedRoomData, error: Error?) -> Bool {
        if let error {
            phase = .failed(error.localizedDescription)
            return false
        }
        return true
    }

    func captureView(didPresent processedResult: CapturedRoom, error: Error?) {
        if let error {
            log.error("Room processing failed: \(error.localizedDescription, privacy: .public)")
            phase = .failed(error.localizedDescription)
            return
        }
        rooms.append(processedResult)
        phase = .roomReady
    }

    // MARK: RoomCaptureSessionDelegate

    func captureSession(_ session: RoomCaptureSession, didProvide instruction: RoomCaptureSession.Instruction) {
        self.instruction = Self.describe(instruction)
    }

    private static func describe(_ instruction: RoomCaptureSession.Instruction) -> String? {
        switch instruction {
        case .moveCloseToWall: "Move closer to the wall"
        case .moveAwayFromWall: "Move away from the wall"
        case .slowDown: "Slow down"
        case .turnOnLight: "Turn on more lights"
        case .lowTexture: "Point at a part of the room with more detail"
        case .normal: nil
        @unknown default: nil
        }
    }
}
