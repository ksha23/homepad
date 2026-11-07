#if os(iOS)
import AVFoundation
import HomePadCore
import MediaPlayer
import Observation
import SwiftUI

/// The system volume as a SwiftUI slider between two speaker symbols, or as a
/// bar (`VolumeSliderStyle`). It controls the active route, so it moves the
/// HomePod's or AirPods' volume when they play, and it follows the hardware
/// buttons. Pair it with `AirPlayButton`.
///
/// A SwiftUI `Slider` lines up with the symbols like any other control. A
/// visible `MPVolumeView` pins its slider to the top of its bounds, and
/// moving that slider inside it fights its own layout, so the slider jumped.
///
///     HStack { SystemVolumeSlider(); AirPlayButton() }
///     SystemVolumeSlider(style: .bar(.vertical))   // Control Center
public struct SystemVolumeSlider: View {
    private let volume = SystemVolumeLevel.shared
    private let style: VolumeSliderStyle
    /// The value under the finger while dragging, so volume reports during the
    /// drag never move the thumb back.
    @State private var dragging: Double?

    public init(style: VolumeSliderStyle = .row) {
        self.style = style
    }

    public var body: some View {
        VolumeSlider(value: Binding(get: { dragging ?? volume.level }, set: { value in
            dragging = value
            volume.set(value)
        }), style: style, label: "Volume") { editing in
            if !editing { dragging = nil }
        }
        .tint(.primary)
        .task { await volume.follow() }
    }
}

/// The system output volume, shared by every volume slider.
///
/// Reading uses `AVAudioSession.outputVolume`, plus the slider of a nearly
/// invisible `MPVolumeView` while a volume slider is on screen: the system keeps
/// that slider on the current route's volume, and `outputVolume` does not report
/// every AirPlay change. Setting has no direct API, so it moves that hidden
/// slider, the same control the system shows. While the view is in the window,
/// the hardware buttons do not show the system volume overlay.
@MainActor
@Observable
public final class SystemVolumeLevel {
    /// One instance, so the window holds one hidden `MPVolumeView`. A slider
    /// that made its own added another view each time SwiftUI rebuilt it.
    public static let shared = SystemVolumeLevel()

    public var level: Double { held.level }
    private var held = HeldVolume(reported: Double(AVAudioSession.sharedInstance().outputVolume))
    @ObservationIgnored private var observation: NSKeyValueObservation?
    @ObservationIgnored private var routeObserver: NSObjectProtocol?
    @ObservationIgnored private weak var hiddenView: MPVolumeView?
    /// The hidden slider's value when last read, to notice the system moving it.
    @ObservationIgnored private var lastSliderValue: Float?
    /// With `-HomePadAudioTrace YES`, every set and report, with the route.
    @ObservationIgnored private let trace = DebugTrace(file: "audio-session-trace.txt", argument: "HomePadAudioTrace")

    private var routeDescription: String {
        AVAudioSession.sharedInstance().currentRoute.outputs.map { "\($0.portName) (\($0.portType.rawValue))" }.joined(separator: ", ")
    }

    private init() {
        observation = AVAudioSession.sharedInstance().observe(\.outputVolume, options: [.new]) { [weak self] _, change in
            guard let value = change.newValue else { return }
            Task { @MainActor in
                self?.trace.log("volume outputVolume reports \(value)")
                self?.held.report(Double(value), at: Date())
            }
        }
        // A new route has its own volume. Keeping the old route's level showed the
        // iPad speaker's 80% on the HomePods' slider, and one touch set them to it.
        routeObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.routeChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.routeChanged() }
        }
        _ = install()
    }

    private func routeChanged() {
        let volume = Double(AVAudioSession.sharedInstance().outputVolume)
        held = HeldVolume(reported: volume)
        lastSliderValue = nil
        trace.log("volume route changed to \(routeDescription), volume \(volume)")
    }

    /// Sets the system volume, 0...1. Returns false when no window is available.
    @discardableResult
    public func set(_ value: Double) -> Bool {
        let value = max(0, min(1, value))
        held.choose(value, at: Date())
        trace.logIfChanged("volume set", "volume set \(String(format: "%.2f", value)) on \(routeDescription)")
        guard let slider = slider() else {
            trace.log("volume set failed: no window for the hidden volume view")
            return false
        }
        slider.value = Float(value)
        slider.sendActions(for: .valueChanged)
        lastSliderValue = slider.value
        return true
    }

    /// Follows the hidden slider while a volume slider is on screen. Call from
    /// a view's `task`. It ends when the task is cancelled.
    public func follow() async {
        while !Task.isCancelled {
            try? await Task.sleep(for: .milliseconds(500))
            readHiddenSlider()
        }
    }

    /// Reports the hidden slider's value when the system moved it. The first
    /// read also counts unless it is 0, which a view that has not caught up reads.
    private func readHiddenSlider() {
        guard let value = slider()?.value else { return }
        defer { lastSliderValue = value }
        let moved = lastSliderValue.map { value != $0 } ?? (value > 0)
        if moved {
            trace.log("volume hidden slider reports \(value) on \(routeDescription)")
            held.report(Double(value), at: Date())
        }
    }

    private func slider() -> UISlider? {
        let view = hiddenView ?? install()
        return view?.subviews.compactMap { $0 as? UISlider }.first
    }

    private func install() -> MPVolumeView? {
        let windows = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.flatMap(\.windows)
        guard let window = windows.first(where: \.isKeyWindow) ?? windows.first else { return nil }
        let view = MPVolumeView(frame: CGRect(x: -400, y: -400, width: 200, height: 40))
        view.alpha = 0.02
        view.isUserInteractionEnabled = false
        view.accessibilityElementsHidden = true
        window.addSubview(view)
        hiddenView = view
        return view
    }
}
#endif
