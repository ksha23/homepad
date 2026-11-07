import UIKit

/// Reads and writes the display brightness. Abstracted so tests can use a fake.
@MainActor
protocol ScreenBrightnessControl: AnyObject {
    /// Brightness from 0 to 1.
    var brightness: Double { get set }
}

/// The real screen, found through the connected window scene
/// (`UIScreen.main` is deprecated since iOS 26).
@MainActor
final class SystemScreenBrightness: ScreenBrightnessControl {
    var brightness: Double {
        get { screen.map { Double($0.brightness) } ?? 0.5 }
        set { screen?.brightness = CGFloat(min(max(newValue, 0), 1)) }
    }

    private var screen: UIScreen? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }?.screen
            ?? UIApplication.shared.connectedScenes.compactMap { ($0 as? UIWindowScene)?.screen }.first
    }
}

/// Moves brightness smoothly toward a target instead of jumping, and remembers
/// the user's own brightness so it can be restored when HomePad leaves the foreground.
@MainActor
final class BrightnessRamp {
    private let control: any ScreenBrightnessControl
    private var task: Task<Void, Never>?
    private(set) var target: Double?
    private var savedUserBrightness: Double?

    init(control: any ScreenBrightnessControl) {
        self.control = control
    }

    var current: Double { control.brightness }

    /// Remembers the brightness the user had before HomePad took over.
    func saveUserBrightness() {
        savedUserBrightness = control.brightness
        target = nil
    }

    /// Puts the user's brightness back (when HomePad goes to the background).
    func restoreUserBrightness() {
        task?.cancel()
        target = nil
        if let savedUserBrightness { control.brightness = savedUserBrightness }
    }

    /// Ramps to `value` over `duration` seconds with an ease-in-out curve.
    /// A zero duration sets it at once.
    func ramp(to value: Double, duration: TimeInterval) {
        guard value != target else { return }
        task?.cancel()
        target = value
        let start = control.brightness
        guard duration > 0, abs(start - value) > 0.005 else {
            control.brightness = value
            return
        }
        let steps = max(1, Int(duration * 30))
        task = Task { [weak self] in
            for step in 1...steps {
                try? await Task.sleep(for: .milliseconds(33))
                guard !Task.isCancelled, let self else { return }
                let t = Double(step) / Double(steps)
                let eased = t * t * (3 - 2 * t)
                self.control.brightness = start + (value - start) * eased
            }
        }
    }
}
