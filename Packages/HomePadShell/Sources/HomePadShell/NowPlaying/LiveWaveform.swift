import HomePadCore
import HomePadUI
import SwiftUI
import UIKit

/// The Now Playing pill's waveform: four bars that move while music plays.
///
/// Nothing here hears the music. Apple Music plays in Apple's own process and
/// Music Assistant plays on speakers elsewhere, so HomePad gets no samples,
/// and reading the microphone instead tracked the room, not the song. The bars
/// keep their own rhythms, like the playing indicator in Apple's Music app.
///
/// Core Animation runs the bars at 30 frames a second, so the app does no work
/// per frame. A SwiftUI timeline redrew them on the main thread at 15 and
/// still cost about 4.5% of a core. They rest, still, when nothing plays, the
/// display dims or Reduce Motion is on.
struct LiveWaveform: View {
    let isPlaying: Bool
    let tint: Color

    @Environment(\.allowsContinuousMotion) private var allowsMotion
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.displayCondition) private var condition
    @Environment(\.self) private var environment

    /// The bars' size, about a title3 symbol.
    static let size = CGSize(width: 22, height: 18)

    var body: some View {
        // Night mode reddens SwiftUI drawing, which does not reach a UIKit view.
        let color = condition == .night ? Theme.nightRed : tint
        WaveformBars(isMoving: isPlaying && allowsMotion && !reduceMotion,
                     color: UIColor(Color(color.resolve(in: environment))))
            .frame(width: Self.size.width, height: Self.size.height)
            .accessibilityHidden(true)
    }
}

private struct WaveformBars: UIViewRepresentable {
    let isMoving: Bool
    let color: UIColor

    func makeUIView(context: Context) -> WaveformBarsView {
        WaveformBarsView()
    }

    func updateUIView(_ view: WaveformBarsView, context: Context) {
        view.color = color
        view.isMoving = isMoving
    }
}

/// The bars as layers, each with a repeating height animation of its own.
final class WaveformBarsView: UIView {
    /// Each bar's heights through one cycle, as a share of the view's height.
    /// Different lengths and durations keep the four from lining up.
    static let patterns: [[CGFloat]] = [
        [0.40, 0.85, 0.55, 1.00, 0.45, 0.70, 0.40],
        [0.75, 0.45, 1.00, 0.60, 0.90, 0.75],
        [0.55, 1.00, 0.70, 0.40, 0.85, 0.55],
        [0.35, 0.65, 0.45, 0.90, 0.55, 0.35],
    ]
    static let durations: [CFTimeInterval] = [1.15, 0.95, 1.3, 1.05]
    /// Heights at rest, the shape of a waveform symbol.
    static let resting: [CGFloat] = [0.45, 0.8, 0.6, 0.35]

    private let bars: [CALayer] = (0..<4).map { _ in CALayer() }

    var color: UIColor = .white {
        didSet {
            guard color != oldValue else { return }
            bars.forEach { $0.backgroundColor = color.cgColor }
        }
    }

    var isMoving = false {
        didSet {
            guard isMoving != oldValue else { return }
            updateAnimations()
        }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        for bar in bars {
            bar.backgroundColor = color.cgColor
            layer.addSublayer(bar)
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let gap = bounds.width * 0.12
        let width = (bounds.width - gap * CGFloat(bars.count - 1)) / CGFloat(bars.count)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for (index, bar) in bars.enumerated() {
            bar.position = CGPoint(x: CGFloat(index) * (width + gap) + width / 2, y: bounds.midY)
            bar.bounds = CGRect(x: 0, y: 0, width: width, height: bounds.height * Self.resting[index])
            bar.cornerRadius = width / 2
        }
        CATransaction.commit()
        updateAnimations()
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        // Layers off screen lose their animations, so they start again here.
        updateAnimations()
    }

    private func updateAnimations() {
        let height = bounds.height
        for (index, bar) in bars.enumerated() {
            bar.removeAnimation(forKey: "wave")
            guard isMoving, window != nil, height > 0 else { continue }
            let pattern = Self.patterns[index]
            let animation = CAKeyframeAnimation(keyPath: "bounds.size.height")
            animation.values = pattern.map { $0 * height }
            animation.keyTimes = pattern.indices.map { NSNumber(value: Double($0) / Double(pattern.count - 1)) }
            animation.timingFunctions = Array(repeating: CAMediaTimingFunction(name: .easeInEaseOut), count: pattern.count - 1)
            animation.duration = Self.durations[index]
            animation.repeatCount = .infinity
            // Each bar starts partway through its cycle.
            animation.timeOffset = Self.durations[index] * Double(index) / Double(bars.count)
            animation.preferredFrameRateRange = CAFrameRateRange(minimum: 20, maximum: 30, preferred: 30)
            bar.add(animation, forKey: "wave")
        }
    }
}
