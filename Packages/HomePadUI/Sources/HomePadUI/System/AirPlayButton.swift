#if os(iOS)
import AVKit
import SwiftUI

/// The system AirPlay button (`AVRoutePickerView`) for any HomePad screen.
/// Tapping it shows Apple's own route picker, including AirPlay 2 groups of
/// several HomePods and Bluetooth headphones.
///
///     AirPlayButton()                       // 44 pt, the primary color
///     AirPlayButton(size: 32, tint: .secondary)
///     AirPlayButton(size: Theme.Size.tapTarget, isGlass: true)   // matches GlassIconButton
public struct AirPlayButton: View {
    private let size: CGFloat
    private let tint: Color?
    private let activeTint: Color
    private let isGlass: Bool
    @State private var showsPicker = false

    /// - Parameters:
    ///   - size: Edge length of the button in points.
    ///   - tint: Symbol color while playing on this iPad. Nil follows the
    ///     appearance (`UIColor.label`), white in Dark and black in Light.
    ///   - activeTint: Symbol color while playing on another device.
    ///   - isGlass: A `GlassIconButton` that opens the picker through
    ///     `airPlayPicker`, as the speaker buttons do, to sit next to other
    ///     glass buttons.
    public init(size: CGFloat = Theme.Size.minTapTarget, tint: Color? = nil, activeTint: Color = .accentColor,
                isGlass: Bool = false) {
        self.size = size
        self.tint = tint
        self.activeTint = activeTint
        self.isGlass = isGlass
    }

    public var body: some View {
        if isGlass {
            GlassIconButton("airplayaudio", label: "AirPlay", size: size) { showsPicker = true }
                .airPlayPicker(isPresented: $showsPicker)
        } else {
            picker(side: size)
        }
    }

    private func picker(side: CGFloat) -> some View {
        RoutePickerRepresentable(tint: tint.map { UIColor($0) } ?? .label, activeTint: UIColor(activeTint))
            .frame(width: side, height: side)
            .accessibilityLabel("AirPlay")
    }
}

public extension View {
    /// Opens Apple's AirPlay picker when `isPresented` turns true, from a
    /// button of the app's own, such as a capsule with the speakers' name.
    /// Attach it to that button: a nearly invisible `AVRoutePickerView` sits
    /// behind it, so the picker opens anchored there. `isPresented` turns back
    /// to false once the picker is asked to open.
    ///
    ///     GlassCapsuleButton(routeName, systemImage: "airplayaudio") { showsAirPlay = true }
    ///         .airPlayPicker(isPresented: $showsAirPlay)
    func airPlayPicker(isPresented: Binding<Bool>) -> some View {
        background {
            if isPresented.wrappedValue {
                AirPlayPickerTrigger(isPresented: isPresented)
                    .allowsHitTesting(false)
            }
        }
    }
}

/// A route picker that taps itself when asked. AVRoutePickerView has no API to
/// open its picker, so this sends its button the tap a finger would.
private struct AirPlayPickerTrigger: UIViewRepresentable {
    @Binding var isPresented: Bool

    func makeUIView(context: Context) -> AVRoutePickerView {
        let picker = AVRoutePickerView()
        picker.prioritizesVideoDevices = false
        // Visible enough for UIKit to present from, invisible to people.
        picker.alpha = 0.02
        picker.isUserInteractionEnabled = false
        return picker
    }

    func updateUIView(_ picker: AVRoutePickerView, context: Context) {
        guard isPresented else { return }
        DispatchQueue.main.async {
            isPresented = false
            Self.button(in: picker)?.sendActions(for: .touchUpInside)
        }
    }

    private static func button(in view: UIView) -> UIButton? {
        if let button = view as? UIButton { return button }
        for child in view.subviews {
            if let button = button(in: child) { return button }
        }
        return nil
    }
}

private struct RoutePickerRepresentable: UIViewRepresentable {
    let tint: UIColor
    let activeTint: UIColor

    func makeUIView(context: Context) -> AVRoutePickerView {
        let picker = AVRoutePickerView()
        picker.backgroundColor = .clear
        picker.prioritizesVideoDevices = false
        return picker
    }

    func updateUIView(_ picker: AVRoutePickerView, context: Context) {
        picker.tintColor = tint
        picker.activeTintColor = activeTint
    }
}
#endif
