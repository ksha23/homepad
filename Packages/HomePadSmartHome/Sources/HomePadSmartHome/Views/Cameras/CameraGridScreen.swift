import HomePadCore
import HomePadUI
import SwiftUI

/// Every camera at once, up to nine live feeds in a grid, pushed inside the Home
/// app from its Cameras header or a camera's grid button. Tap one for full screen.
struct CameraGridScreen: View {
    static let maximumFeeds = 9

    @Environment(UnifiedSmartHomeService.self) private var service
    let onBack: () -> Void
    let onOpen: (HomeCamera.ID) -> Void

    private var shown: [HomeCamera] { Array(service.cameras.prefix(Self.maximumFeeds)) }

    var body: some View {
        AppScreen("Cameras", onBack: onBack, backLabel: service.homeName) {
            if shown.isEmpty {
                EmptyStateView("No Cameras", message: "Cameras from Apple Home and Home Assistant appear here.", systemImage: "video.slash")
            } else {
                grid
            }
        }
        .fullScreenSurfaceContent()
        .background(Color.screenBackground.ignoresSafeArea())
    }

    /// Tiles in the camera's own 16:9 shape, as large as fit, centered.
    private var grid: some View {
        GeometryReader { geometry in
            let spacing = Theme.Spacing.m
            let layout = CameraGridLayout.best(count: shown.count, in: geometry.size, spacing: spacing)
            let rows = stride(from: 0, to: shown.count, by: layout.columns).map { Array(shown[$0..<min($0 + layout.columns, shown.count)]) }
            VStack(spacing: spacing) {
                ForEach(rows.indices, id: \.self) { index in
                    HStack(spacing: spacing) {
                        ForEach(rows[index]) { camera in
                            CameraTile(camera: camera) { onOpen(camera.id) }
                                .frame(width: layout.tile.width, height: layout.tile.height)
                        }
                    }
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
    }
}
