import HomePadCore
import HomePadUI
import SwiftUI

/// One feed on the Cameras face: the Smart Home module's shared camera view
/// (live up close, stills from afar), or polled snapshots when that module is
/// absent. From across the room the pictures are all there is, square
/// inside the face's rounded grid. Up close the feeds round their corners
/// and the camera's name and the time the picture was taken fade in. Behind
/// the Home Screen the doorbell's ring and the spinner leave too.
struct CameraFeedTile: View {
    let camera: HomeCamera
    let image: UIImage?
    let updatedAt: Date?
    let isPlaceholder: Bool
    let isRinging: Bool
    /// The face's near look: rounded and live, with the name and the time.
    let isNear: Bool

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: isNear ? Theme.Radius.tile : 0, style: .continuous)
        ZStack(alignment: .bottomLeading) {
            shape.fill(Color.white.opacity(0.08))
                .overlay {
                    if SmartHomeCameraView.renderer != nil {
                        // Live video up close, refreshing stills from across the room to save power.
                        SmartHomeCameraView(cameraID: camera.id, mode: isNear ? .live : .still)
                    } else if let image {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                            .saturation(isPlaceholder ? 0.55 : 1)
                            .transition(.opacity)
                    } else {
                        ProgressView()
                            .faceForeground()
                    }
                }
                .overlay {
                    // A gentle vignette so labels stay readable on bright feeds,
                    // only while they show.
                    LinearGradient(colors: [.clear, .black.opacity(0.45)], startPoint: .center, endPoint: .bottom)
                        .opacity(isNear ? 1 : 0)
                }
            if isNear {
                caption
                    .padding(Theme.Spacing.m)
                    .transition(.proximityDetail)
            }
        }
        .clipShape(shape)
        .overlay {
            if isRinging {
                shape.strokeBorder(Color.green, lineWidth: 5)
                    .faceForeground()
            }
        }
        .animation(.easeInOut(duration: 0.4), value: image)
        .nightModeAware()
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(camera.name) camera")
    }

    private var caption: some View {
        GlassPill(camera.name, systemImage: camera.isDoorbell ? "bell.fill" : "video.fill") {
            if isPlaceholder {
                Text("Demo").font(.footnote.weight(.bold)).foregroundStyle(.secondary)
            } else if let updatedAt {
                Text(updatedAt, format: .dateTime.hour().minute().second())
                    .font(.footnote.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
        .foregroundStyle(.white)
    }
}
