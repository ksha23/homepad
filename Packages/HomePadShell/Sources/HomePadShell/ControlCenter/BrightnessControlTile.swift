import HomePadUI
import SwiftUI

/// Big vertical brightness slider. A manual change holds until the display
/// condition changes (for example when the room goes dark or nobody is around).
struct BrightnessControlTile: View {
    @Environment(KioskController.self) private var kiosk
    @State private var value = 0.5

    var body: some View {
        BigSlider(value: Binding(
            get: { value },
            set: { newValue in
                value = newValue
                kiosk.setManualBrightness(newValue)
            }
        ), systemImage: value < 0.3 ? "sun.min.fill" : "sun.max.fill")
        .onAppear { value = kiosk.currentBrightness }
        .accessibilityLabel("Brightness")
    }
}
