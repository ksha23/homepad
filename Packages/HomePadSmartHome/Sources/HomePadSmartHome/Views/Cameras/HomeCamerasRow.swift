import HomePadCore
import HomePadUI
import SwiftUI

/// The Home app's Cameras section, as on HomeView: a "Cameras" header that opens
/// every camera in a grid, over a compact strip of snapshot tiles that scrolls
/// sideways. A tile opens its camera full screen.
struct HomeCamerasRow: View {
    @Environment(\.proximity) private var proximity
    let cameras: [HomeCamera]
    /// Bigger tiles, for a room with nothing else to show.
    var isLarge = false
    let onShowAll: () -> Void
    let onOpen: (HomeCamera.ID) -> Void
    @State private var rowWidth: CGFloat = 1000

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            header
            let width = tileWidth(in: rowWidth)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Theme.Spacing.m) {
                    ForEach(cameras) { camera in
                        // Snapshots, like HomeView: live video starts full screen.
                        CameraTile(camera: camera, purpose: .still) { onOpen(camera.id) }
                            .frame(width: width, height: width / CameraGridLayout.aspectRatio)
                    }
                }
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.viewAligned)
            .scrollClipDisabled()
            .onGeometryChange(for: CGFloat.self, of: \.size.width) { rowWidth = $0 }
        }
    }

    private var header: some View {
        Button(action: onShowAll) {
            HStack(spacing: Theme.Spacing.xs) {
                SectionHeader("Cameras", systemImage: "video.fill")
                Image(systemName: "chevron.forward")
                    .font(.headline)
                    .foregroundStyle(.tertiary)
            }
            // A full-size target without making the header taller.
            .padding(.vertical, Theme.Spacing.s)
            .contentShape(Rectangle())
            .padding(.vertical, -Theme.Spacing.s)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("All Cameras")
    }

    /// A compact strip, as in Apple Home on iPad: from arm's length five tiles
    /// across a 13-inch landscape screen (about 130 points tall), four from
    /// across the room, two or three when large. Large tiles never leave a
    /// column empty, so a room's only camera fills the row. When there are
    /// more, the next one peeks in, so the row reads as one that scrolls.
    private func tileWidth(in width: CGFloat) -> CGFloat {
        let target: CGFloat = isLarge ? 440 : proximity >= .mid ? 220 : 300
        let fit = max(2, (width / target).rounded(.down))
        let columns = isLarge ? max(1, min(fit, CGFloat(cameras.count))) : fit
        let peek: CGFloat = CGFloat(cameras.count) > columns ? 0.25 : 0
        let gaps = columns - 1 + (peek > 0 ? 1 : 0)
        return (width - Theme.Spacing.m * gaps) / (columns + peek)
    }
}
