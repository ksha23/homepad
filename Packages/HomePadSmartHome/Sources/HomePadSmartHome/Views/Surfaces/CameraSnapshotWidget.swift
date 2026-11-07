import HomePadCore
import HomePadUI
import SwiftUI

/// A camera snapshot that refreshes every few seconds. Prefers the doorbell camera.
struct CameraSnapshotWidget: View {
    @Environment(UnifiedSmartHomeService.self) private var service
    let size: WidgetSize

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Theme.Radius.tile, style: .continuous)
        let camera = service.doorbellCameraID.flatMap(service.camera) ?? service.cameras.first
        ZStack(alignment: .bottomLeading) {
            if let camera {
                CameraFeedView(camera: camera, purpose: .still)
                label(camera.name)
            } else {
                CameraPlaceholder(message: "No cameras", isLoading: false)
            }
        }
        .clipShape(shape)
        // The name's glass sits on the picture in every appearance.
        .environment(\.colorScheme, .dark)
        .nightModeAware()
    }

    /// The camera's name over the picture. The small widget gets the name alone
    /// on one short line: the larger sizes' capsule, symbol and headline type
    /// wrapped "Front Door" onto two lines there and covered a third of the picture.
    @ViewBuilder
    private func label(_ name: String) -> some View {
        if size == .small {
            Text(name)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.85)
                .foregroundStyle(.white)
                .padding(.horizontal, Theme.Spacing.s)
                .padding(.vertical, Theme.Spacing.xs)
                .glassEffect(.regular, in: .capsule)
                .padding(Theme.Spacing.s)
        } else {
            Label(name, systemImage: "video.fill")
                .font(.headline)
                .foregroundStyle(.white)
                .padding(.horizontal, Theme.Spacing.m)
                .padding(.vertical, Theme.Spacing.xs)
                .glassEffect(.regular, in: .capsule)
                .padding(Theme.Spacing.s)
        }
    }
}
