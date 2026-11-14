import HomePadCore
import HomePadUI
import SwiftUI

/// The recognition debug view: on the face screen, while Show What the Sensors
/// See is on, the camera's and the depth sensor's view of the face, with what
/// recognition made of them. It takes no touches, so the face works as usual.
/// The pictures stay on the iPad, in memory, and are never saved.
struct RecognitionDebugOverlay: View {
    let presence: LivePresenceService
    let settings: SettingsStore
    @Environment(\.isOnFace) private var isOnFace

    var body: some View {
        if isOnFace, settings[PresenceSettings.recognitionDebug], let state = presence.debugView {
            RecognitionDebugPanel(state: state)
                .padding(Theme.Spacing.l)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }
}

private struct RecognitionDebugPanel: View {
    let state: RecognitionDebugState

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 8) {
                picture(state.frame.camera, title: "Camera") { size in cameraMarks(size) }
                picture(state.frame.depth, title: "Depth (near red, far blue)") { size in depthMarks(size) }
                if let shaded = state.frame.shaded {
                    picture(shaded, title: "Depth as a lit surface") { size in shadedMarks(size) }
                }
                if let face = state.frame.faceDepth {
                    let age = state.frame.faceAgeSeconds.map { String(format: " (%.1f s ago)", $0) } ?? ""
                    picture(face, title: "Face, nose to 8 cm back" + age) { _ in EmptyView() }
                }
            }
            VStack(alignment: .leading, spacing: 2) {
                ForEach(Array(state.lines.enumerated()), id: \.offset) { _, line in
                    Text(line)
                }
            }
            .font(.caption2.monospaced())
        }
        .foregroundStyle(.white)
        .padding(10)
        .background(.black.opacity(0.9), in: RoundedRectangle(cornerRadius: 14))
        .frame(maxWidth: 1100, alignment: .leading)
    }

    private func picture<Marks: View>(
        _ image: CGImage?, title: String, @ViewBuilder marks: @escaping (CGSize) -> Marks
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption2.weight(.semibold))
            if let image {
                Image(decorative: image, scale: 1)
                    .resizable()
                    .aspectRatio(CGFloat(image.width) / CGFloat(max(image.height, 1)), contentMode: .fit)
                    .frame(height: 160)
                    .overlay { GeometryReader { proxy in marks(proxy.size) } }
            } else {
                Color.white.opacity(0.1)
                    .frame(width: 210, height: 160)
                    .overlay { Text("nothing yet").font(.caption2) }
            }
        }
    }

    /// The face Vision found in the shaded depth.
    @ViewBuilder
    private func shadedMarks(_ size: CGSize) -> some View {
        if let box = state.frame.shadedBox {
            Rectangle()
                .stroke(.yellow, lineWidth: 2)
                .frame(width: box.width * size.width, height: box.height * size.height)
                .position(x: box.midX * size.width, y: box.midY * size.height)
        }
    }

    /// The faces ARKit or Vision found.
    private func cameraMarks(_ size: CGSize) -> some View {
        ForEach(Array(state.frame.faceBoxes.enumerated()), id: \.offset) { _, box in
            Rectangle()
                .stroke(.green, lineWidth: 2)
                .frame(width: box.width * size.width, height: box.height * size.height)
                .position(x: box.midX * size.width, y: box.midY * size.height)
        }
    }

    /// The followed head, the nose tip found by depth alone, and how far the
    /// face's depth signature reaches around it.
    @ViewBuilder
    private func depthMarks(_ size: CGSize) -> some View {
        if let head = state.frame.head {
            Ellipse()
                .stroke(.white, style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                .frame(width: head.width * size.width, height: head.height * size.height)
                .position(x: head.midX * size.width, y: head.midY * size.height)
        }
        if let nose = state.frame.nose {
            if let reach = state.frame.reach {
                Ellipse()
                    .stroke(.yellow, lineWidth: 1.5)
                    .frame(width: reach.width * 2 * size.width, height: reach.height * 2 * size.height)
                    .position(x: nose.x * size.width, y: nose.y * size.height)
            }
            Circle()
                .fill(state.frame.noseRejected ? .red : .white)
                .frame(width: 7, height: 7)
                .position(x: nose.x * size.width, y: nose.y * size.height)
        }
    }
}
