import AVFoundation
import HomePadCore
import Observation

/// Keeps the current system route (AirPlay, Bluetooth such as AirPods, wired,
/// built-in) and whether other AirPlay routes are nearby.
///
/// iOS only reveals the route in use. Speakers that are available but not
/// selected are invisible to apps, so `AVRouteDetector` answers only "are there
/// other routes" and `AVRoutePickerView` does the choosing.
@MainActor
@Observable
final class AudioRouteMonitor {
    private(set) var ports: [AudioRoutePort] = []
    private(set) var multipleRoutesDetected = false

    /// Called after every route change with the previous ports and the reason.
    @ObservationIgnored var onChange: ((_ previous: [AudioRoutePort], _ reason: AVAudioSession.RouteChangeReason) -> Void)?
    @ObservationIgnored private let detector = AVRouteDetector()
    @ObservationIgnored private var detectionClients = 0
    @ObservationIgnored private var observers: [NSObjectProtocol] = []
    @ObservationIgnored private let demoPorts: [AudioRoutePort]?

    /// - Parameter demoPorts: fixed ports for simulator screenshots, nil for the real route.
    init(demoPorts: [AudioRoutePort]? = nil) {
        self.demoPorts = demoPorts
        ports = demoPorts ?? AudioRoute.currentPorts
        multipleRoutesDetected = demoPorts != nil
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: AVAudioSession.routeChangeNotification, object: nil, queue: .main) { [weak self] note in
            let reason = (note.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt)
                .flatMap(AVAudioSession.RouteChangeReason.init) ?? .unknown
            MainActor.assumeIsolated { self?.refresh(reason: reason) }
        })
        observers.append(center.addObserver(forName: .AVRouteDetectorMultipleRoutesDetectedDidChange, object: detector, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.demoPorts == nil else { return }
                self.multipleRoutesDetected = self.detector.multipleRoutesDetected
            }
        })
    }

    var outputs: [AudioOutput] { RouteNaming.outputs(for: ports) }
    var currentRouteName: String { RouteNaming.routeName(for: ports) }
    var headphonesActive: Bool { ports.contains(where: \.isHeadphones) }
    var isAirPlayActive: Bool { ports.contains { $0.kind == .airPlay } }

    /// Turns on route detection while someone looks at a speaker UI. Detection costs power, so it is reference counted.
    func beginDetection() {
        detectionClients += 1
        guard demoPorts == nil else { return }
        detector.isRouteDetectionEnabled = true
        multipleRoutesDetected = detector.multipleRoutesDetected
    }

    func endDetection() {
        detectionClients = max(0, detectionClients - 1)
        if detectionClients == 0 { detector.isRouteDetectionEnabled = false }
    }

    func refresh(reason: AVAudioSession.RouteChangeReason = .unknown) {
        guard demoPorts == nil else { return }
        let previous = ports
        ports = AudioRoute.currentPorts
        if previous != ports || reason != .unknown {
            onChange?(previous, reason)
        }
    }
}
