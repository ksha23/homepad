import HomePadUI
import SwiftUI

/// Big vertical volume slider, like brightness beside it and like iPadOS.
/// It sets the system volume, so it moves the AirPods' or HomePod's volume
/// when they play and follows the hardware buttons. Output choice lives on
/// the media tile's AirPlay button.
struct SystemVolumeTile: View {
    var body: some View {
        SystemVolumeSlider(style: .bar(.vertical))
    }
}
