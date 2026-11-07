import SwiftUI

/// Draws the simulator's demo feed by polling the latest frame a few times a second.
/// Fills its frame like the live preview layer does, without growing past it.
struct DemoFeedView: View {
    let hub: FrameHub

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1.0 / 8)) { _ in
            Color.black.overlay {
                if let frame = hub.latestFrame, let image = FrameEncoder.cgImage(from: frame.pixelBuffer, maxDimension: 960) {
                    Image(decorative: image, scale: 1)
                        .resizable()
                        .scaledToFill()
                }
            }
            .clipped()
        }
    }
}
