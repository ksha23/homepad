@preconcurrency import HomeKit
import SwiftUI

/// HomeKit's own `HMCameraView`, which is the only way to show HomeKit video.
/// It stretches the picture to whatever bounds it gets, so it is given the
/// camera's own shape (`aspectRatio`) and then cropped or fitted into the frame.
struct HomeKitCameraSourceView: View {
    let source: HMCameraSource?
    @Environment(\.cameraContentMode) private var contentMode

    var body: some View {
        let ratio = source.map { CGFloat($0.aspectRatio) }.flatMap { $0 > 0 ? $0 : nil } ?? CameraGridLayout.aspectRatio
        Color.black
            .overlay {
                HomeKitCameraLayer(source: source)
                    .aspectRatio(ratio, contentMode: contentMode)
            }
            .clipped()
    }
}

private struct HomeKitCameraLayer: UIViewRepresentable {
    let source: HMCameraSource?

    func makeUIView(context: Context) -> HMCameraView {
        let view = HMCameraView()
        view.backgroundColor = .black
        return view
    }

    func updateUIView(_ view: HMCameraView, context: Context) {
        if view.cameraSource !== source { view.cameraSource = source }
    }
}
