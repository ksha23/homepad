import AVKit
import UIKit

/// Opens the system AirPlay and Bluetooth picker from code, for the assistant,
/// the preferred-speaker prompt.
///
/// iOS 27 still has no public API to choose an AirPlay route programmatically,
/// so HomePad keeps one invisible `AVRoutePickerView` in the window and triggers
/// its button. The picker anchors near the top-right corner, where HomePad's
/// AirPlay buttons live.
@MainActor
enum RoutePickerPresenter {
    private static weak var picker: AVRoutePickerView?

    /// Shows the picker. Returns false when there is no window or the picker's button could not be found.
    @discardableResult
    static func present() -> Bool {
        guard let window = activeWindow() else { return false }
        let picker = self.picker ?? install(in: window)
        guard let button = firstButton(in: picker) else { return false }
        button.sendActions(for: .touchUpInside)
        return true
    }

    private static func install(in window: UIWindow) -> AVRoutePickerView {
        let picker = AVRoutePickerView(frame: CGRect(x: window.bounds.maxX - 96, y: 28, width: 44, height: 44))
        picker.autoresizingMask = [.flexibleLeftMargin, .flexibleBottomMargin]
        picker.alpha = 0.02
        picker.isUserInteractionEnabled = false
        picker.accessibilityElementsHidden = true
        window.addSubview(picker)
        self.picker = picker
        return picker
    }

    private static func firstButton(in view: UIView) -> UIButton? {
        for subview in view.subviews {
            if let button = subview as? UIButton { return button }
            if let nested = firstButton(in: subview) { return nested }
        }
        return nil
    }

    private static func activeWindow() -> UIWindow? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let windows = scenes.sorted { lhs, _ in lhs.activationState == .foregroundActive }.flatMap(\.windows)
        return windows.first(where: \.isKeyWindow) ?? windows.first
    }
}
